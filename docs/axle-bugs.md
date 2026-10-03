# Bugs du compilateur Axle rencontrés

Relevé pendant la passe d'optimisation de voxel-axle. Toolchain :
`axle 0.13.1-dev (ba29a5f)`, Windows 11, x86_64.

---

## 1. Crash de codegen : `store_at` i1 contre i8

```
error[CODEGEN]: Internal codegen error: IR-assembly invariant violated:
store_at: the value is not what the address holds
(the address holds "i1", the value is "i8") — sema↔codegen contract breach
```

**Reproduction** — dépôt public, aucun patch nécessaire :

```
git clone https://github.com/Axle-lang/smalt && cd smalt/examples/hello_window
axle build -O 3
```

**Portée.** Trois exemples sur huit meurent, et ce sont les trois qui ouvrent une
fenêtre et pompent des évènements :

| échoue | passe |
|---|---|
| `hello_window`, `spinning_cube`, `ui_panel` | `audio_check`, `donut3d`, `mario3d`, `proc_check`, `self_check` |

Indépendant de tout le reste : les trois émissions (`binary`, `object`, `llvm`),
les deux cibles (hôte et `x86_64-unknown-linux-gnu`), et présent aussi bien au
commit `4465f5d` qu'à `1d05a6a`. Ce n'est donc pas une régression récente.

**Ce que je n'ai pas réussi à réduire.** Tous ces cas compilent seuls, donc le
déclencheur est ailleurs : `bool` dans un `struct`, `malloc<bool>`, `enum : i8`,
champ `bool` de classe, trait rendant un `bool`, `bool` dans un
`extern "C" struct`, `bool` rendu par une méthode de `struct`.

La signature dit qu'une case typée `bool` (i1) reçoit un octet. Le point commun
des trois exemples qui tombent est la boucle d'évènements, donc je regarderais
d'abord du côté de `EventQueue` / `KeyboardState` / `MouseState`.

---

## 2. `axle fmt` panique sur un caractère non-ASCII en commentaire

```
thread 'main' panicked at crates\6-tools\axle_fmt\src\lower\punct.rs:65:39:
byte index 15 is not a char boundary; it is inside '—' (bytes 13..16)
```

**Reproduction** : `cd voxel-axle && axle fmt --check src`

**Cause.** `authored_layout` fait `src[a..b]` avec des offsets qui tombent au
milieu d'un caractère multi-octets :

```rust
pub fn authored_layout(src: &str, open_after: u32, first: u32) -> Layout {
    let (a, b) = (open_after as usize, first as usize);
    if b <= src.len() && a <= b && src[a..b].contains('\n') {   // ← ici
```

Les bornes `b <= src.len()` et `a <= b` protègent du dépassement mais pas de la
frontière de caractère. Soit les offsets sont comptés en caractères ailleurs et
en octets ici, soit il manque un `src.get(a..b)`.

**Conséquence.** Le formateur est inutilisable sur toute base de code qui met de
la ponctuation typographique en commentaire, ce qui est le style de voxel-axle
et de smalt de bout en bout. Il meurt sur le premier fichier rencontré.

---

## 3. Un `const` de haut niveau ne peut pas être d'un type non signé

```
[E0001] Top-level global `AXIS_VERTICAL` is declared `value`
        but its initializer is `integer`
```

**Reproduction** : `const AXIS_VERTICAL : u32 = 0;` au niveau fichier.

Refusé aussi sous ces formes :

- `const AXIS_VERTICAL : u32 = 0 as u32;`
- `class WlAxis { static VERTICAL : u32 = 0; }`

**Conséquence.** Une constante comparée à un `u32` venant d'une signature FFI
(ici un champ de protocole Wayland) force un `as i32` à chaque point d'usage,
alors que l'intention était justement de supprimer la conversion.

**Diagnostic.** Le message parle d'un type `value` que l'utilisateur n'a jamais
écrit, et ne nomme pas le type refusé ni pourquoi. Quelque chose comme « un
global de haut niveau ne peut pas être d'un type non signé » serait exploitable
tel quel.

---

## 4. La compilation croisée n'a pas de stdlib pour la cible

```
error[CODEGEN]: libaxle_stdlib.a not found.
Searched (in order):
  - ...\axle\target\release\libaxle_stdlib.a
  - ...\axle\target\release\lib\libaxle_stdlib.a
  - ...\axle\target\libaxle_stdlib.a
```

**Reproduction** : `axle build --target x86_64-unknown-linux-gnu` depuis Windows.

Les trois chemins fouillés sont tous dans le répertoire de release de l'hôte, et
aucun n'est propre à la cible. Donc un hôte Windows peut *analyser* une autre
cible — `axle check --target` marche très bien et m'a servi à valider le port
Wayland — mais ne peut pas en *lier* une.

---

## 5. `--target-cpu native` casse la compilation au lieu d'être refusé

**Reproduction** : `axle build -O 3 --target-cpu native`

```
'native' is not a recognized processor for this target (ignoring processor)
   … (répété une fois par unité de codegen)
LLVM ERROR: 64-bit code requested on a subtarget that doesn't support it!
```

`native` est passé tel quel à LLVM, qui ne le connaît pas, l'ignore, retombe sur
un sous-ensemble sans 64 bits, puis meurt sur un message qui ne dit rien du vrai
problème. Deux issues acceptables : résoudre `native` vers le CPU de l'hôte, ou
le refuser en amont avec un message clair. Un nom valide comme `znver5` marche.

---

## 6. Mineur : on ne peut pas analyser le port d'une dépendance depuis un consommateur

`--features` « ne va pas plus loin que la crate racine », ce qui est documenté.
Mais la conséquence est qu'un projet consommateur ne peut pas vérifier un port
de sa dépendance qui est derrière un feature : `axle check --features wayland`
depuis l'exemple reste vert même après avoir cassé volontairement un fichier
Wayland de smalt, parce que le feature n'atteint jamais smalt.

Il faut lancer `axle check` depuis la dépendance elle-même, ce qui marche mais
sort alors un faux positif :

```
[E0001] no `main` function defined — every Axle program must declare
        a top-level `fn main(): i32` or `fn main(): void`
```

sur une crate qui est une bibliothèque. Deux petites demandes : pouvoir demander
un feature de dépendance depuis l'arête `[dependencies]` qui la nomme, et ne pas
exiger de `main` d'une crate bibliothèque.

## 7. `axle fmt` supprime le mot-clé `static` des champs de classe

Le plus grave de la liste : le formateur change le sens du programme. Toutes les
classes de configuration du projet déclarent des constantes `static`, lues par le
reste du code sous la forme `Noise::TEMP_SCALE`. Un passage de `axle fmt` les
réécrit sans le mot-clé.

Avant :

```
class Gameplay {
    static REACH_DIST : f64 = 5.0;   // how far the look-ray reaches, in blocks
    static EDIT_COOLDOWN : i32 = 10; // frames between repeated digs/places
}
```

Après :

```
class Gameplay {
    REACH_DIST    : f64 = 5.0; // how far the look-ray reaches, in blocks
    EDIT_COOLDOWN : i32 = 10;  // frames between repeated digs/places
}
```

L'alignement des deux-points et des commentaires est le travail attendu ; la
perte de `static` transforme des constantes de classe en champs d'instance. Sur
ce projet le formateur a touché 19 fichiers de configuration d'un coup, donc un
`axle fmt` suivi d'un commit sans relecture casse le programme en silence.

## 8. `axle fmt` panique sur un fichier valide

Sur le même passage, et sur un fichier que `axle build -O 3` compile sans une
seule erreur :

```
thread 'main' (10412) panicked at crates\6-tools\axle_fmt\src\lower\punct.rs:65:39:
```

Le message imprime ensuite le début du commentaire de tête du fichier
(`src/game/physcheck.axle`, un commentaire de bloc `//` de vingt lignes suivi
d'un bloc `use`). Le formateur s'arrête là, donc les fichiers qui suivent dans
l'ordre de parcours ne sont pas formatés du tout — l'échec est partiel et
silencieux quant à ce qui reste à faire.
