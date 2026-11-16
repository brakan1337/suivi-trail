# Suivi du trail en direct

[![CI](https://github.com/brakan1337/suivi-trail/actions/workflows/ci.yml/badge.svg)](https://github.com/brakan1337/suivi-trail/actions/workflows/ci.yml)

Le jour de la course, les tapis de chronométrage envoient les passages des coureurs à chaque point de contrôle. Les spectateurs suivent le classement en direct. Le PC sécurité voit tout de suite qui n'a plus donné de nouvelles, ou qui a dépassé une barrière horaire.

**Elixir · Phoenix LiveView · OTP (GenServer, superviseurs, Registry) · PubSub · ExUnit · GitHub Actions**

![Le classement en direct](docs/classement.jpg)

## Le brief

> Ce projet est un cas d'étude. La course et ses coureurs sont fictifs ; le brief sert à justifier les choix techniques.

C'est le même organisateur que [les inscriptions](https://github.com/brakan1337/inscriptions-trail), pour un tout autre besoin. Les inscriptions s'étalent sur des mois et tournent très bien en PHP sur un hébergement mutualisé.

Le jour de la course, tout change. 400 coureurs passent devant six tapis de chronométrage, 3 000 personnes suivent en direct, et le PC sécurité doit savoir en quelques minutes qu'un coureur n'est pas arrivé au point suivant. Un hébergement mutualisé ne tient pas des milliers de connexions ouvertes en même temps, et un serveur qui tombe ce jour-là n'a pas droit à l'erreur.

**Pourquoi Elixir :**

- **Des milliers de connexions temps réel.** Chaque page ouverte est un processus de la machine virtuelle Erlang, qui pèse quelques kilo-octets. Phoenix LiveView pousse les mises à jour sans qu'on écrive de JavaScript.
- **Une panne n'arrête pas tout.** Les processus sont surveillés : celui qui plante est relancé, et il relit son journal. Une erreur sur un passage ne fait pas tomber le classement.
- **L'heure et le parallélisme sont au cœur du langage.** Un processus par épreuve, des messages entre eux : pas de verrous à gérer à la main.

Deux langages pour le même client, chacun pour un besoin différent. C'est le choix assumé de ce projet.

## Ce que fait l'application

- **Classement en direct** : le point le plus avancé d'abord, puis l'heure. Il se filtre par sexe, par catégorie, par nom ou par dossard, avec un rang propre à la sélection. Le nombre de coureurs passés à chaque point s'affiche aussi.
- **Fiche d'un coureur** : ses heures de passage, son rang à chaque point et son heure d'arrivée estimée.
- **PC sécurité**, protégé par mot de passe :
  - **Hors délai** : la barrière horaire du point suivant est passée sans que le coureur y soit arrivé.
  - **Sans nouvelles** : le coureur se tait depuis bien plus longtemps que le temps prévu pour son tronçon.
  - Chaque alerte se marque « prise en charge » ou se transforme en abandon. Les cas les plus urgents s'affichent en premier.
- **API des tapis** : `POST /api/passages`, par paquets, avec le jeton du chronométreur. Chaque ligne reçoit sa propre réponse.

![Le PC sécurité](docs/securite.jpg)

## Le calcul qui compte : le kilomètre-effort

Pour savoir si un coureur est en retard, il faut savoir combien de temps **lui** devrait mettre sur **ce** tronçon. Un tronçon de 8 km avec 640 m de montée ne se court pas comme 8 km de plat.

Le trail utilise pour cela le **kilomètre-effort** : 100 m de dénivelé positif comptent comme un kilomètre de plat. L'application calcule l'allure de chaque coureur depuis le départ, en secondes par km-effort. Elle en déduit le temps attendu sur le tronçon suivant. Une alerte se déclenche au-delà de 1,5 fois ce temps, plus 15 minutes.

Un coureur lent qui reste dans son propre rythme n'est donc pas signalé. Un coureur rapide qui s'arrête l'est vite. Tout est dans [`course.ex`](lib/suivi_trail/course.ex), en fonctions pures : l'heure est toujours passée en paramètre, ce qui permet de tester chaque règle à la seconde près.

## Architecture

```
Tapis de chronométrage ──POST /api/passages──┐
Simulateur (en développement) ───────────────┤
                                             ▼
                     CourseServeur (un GenServer par épreuve, supervisé)
                       ├─ écrit chaque passage dans un journal sur disque
                       ├─ recalcule les alertes toutes les 15 s
                       └─ diffuse le classement au plus une fois par seconde
                                             │ Phoenix.PubSub
                     ┌───────────────────────┼───────────────────────┐
                     ▼                       ▼                       ▼
                DirectLive              CoureurLive              SecuriteLive
          (un processus par page)
```

- **Diffusion regroupée.** Le processus de la course ne prévient pas les pages à chaque passage. Il diffuse l'état au plus une fois par seconde. Qu'il y ait 10 ou 3 000 pages ouvertes, il fait le même travail. Chaque page calcule ensuite son propre classement filtré, dans son propre processus.
- **Journal et reprise.** Chaque passage accepté est écrit sur disque avant d'être confirmé. Si le processus plante, le superviseur le relance, et il relit son journal : un test le tue avec `Process.exit(pid, :kill)` et vérifie qu'il retrouve l'état exact.
- **Les tapis sont imparfaits.** Une puce lue deux fois au même point ne compte qu'une fois. Un passage qui arrive en retard, parce qu'un point est en zone blanche, est rangé à sa place.
- **Le PC sécurité a sa propre `live_session`.** Avec LiveView, passer d'une page à l'autre au sein d'une même session se fait par le WebSocket, sans repasser par les contrôles HTTP. En isolant le PC sécurité, on impose une vraie requête, donc le mot de passe. Un test le vérifie.
- **Une horloge de course.** En simulation, l'heure de course part de 7 h 28 et défile 60 fois plus vite. Toute l'application, alertes comprises, vit à cette heure-là.

## Lancer le projet

Avec Erlang/OTP et Elixir installés :

```bash
mix setup
```

```bash
mix phx.server
```

Puis http://localhost:4000. En développement, une course simulée démarre : 396 coureurs, 60 fois plus vite que le temps réel, donc une minute réelle par heure de course. Certains coureurs faiblissent, quelques-uns s'arrêtent sans prévenir. Le PC sécurité se trouve sur `/securite`, avec l'identifiant **securite** et le mot de passe de développement **securite-dev**.

Pour envoyer un passage comme le ferait un tapis, avec le jeton de développement :

```bash
curl -X POST localhost:4000/api/passages -H "Authorization: Bearer jeton-de-developpement-chronometreur" -H "Content-Type: application/json" -d '{"passages":[{"dossard":12,"point":"BRU","heure":"2027-05-15T08:41:12"}]}'
```

En production, `JETON_CHRONOMETREUR`, `MOT_DE_PASSE_SECURITE` et `JOURNAL_DIR` viennent de l'environnement.

## Tests

```bash
mix test
```

33 tests :

- **Règles de course** : passages refusés ou ignorés, passages arrivés dans le désordre, classement et filtres, abandons, fiche et estimation d'arrivée, km-effort, alertes de retard calculées à la main, barrière horaire, alertes traitées.
- **Processus de course** : diffusion regroupée, et un processus tué puis relancé qui relit son journal.
- **API des tapis** : un paquet où chaque ligne a sa réponse, le jeton obligatoire, un envoi mal formé.
- **Pages en direct** : mise à jour sans rechargement, filtres, fiche d'un coureur, accès au PC sécurité, prise en charge et abandon.

La CI compile avec les avertissements bloquants, vérifie la mise en forme et les dépendances, lance les tests et construit les feuilles de style.
