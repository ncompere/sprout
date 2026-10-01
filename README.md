# Sprout

Application iOS native en français pour suivre ses plantes d’intérieur et leurs arrosages. SwiftUI, SwiftData, iOS 17+, sans dépendance externe.

## Lancer l’application

1. Ouvrir `Sprout.xcodeproj` dans Xcode et sélectionner le schéma partagé **Sprout**.
2. Choisir un simulateur iPhone avec iOS 17 ou une version ultérieure. Installer un runtime iOS depuis les réglages de Xcode si nécessaire.
3. Lancer avec **⌘R**. Sur un iPhone physique, choisir son équipe dans **Signing & Capabilities** et un identifiant de bundle personnel.

Le dépôt contient le projet et le schéma : aucun générateur de projet ou gestionnaire de paquets n’est nécessaire.

## Utilisation

- **Mes plantes** : ajouter une plante, choisir son nom, sa première échéance et sa fréquence en jours (7 jours par défaut). Les plantes en retard sont regroupées en haut ; les autres sont triées par échéance.
- **Fiche plante** : modifier le nom ou le planning, enregistrer un arrosage aujourd’hui, ou supprimer la plante après confirmation.
- **Calendrier** : parcourir les mois et toucher un jour pour consulter les plantes concernées. Les symboles distinguent les arrosages prévus, effectués et en retard. Le bouton **Aujourd’hui** revient au jour courant.

La première échéance s’applique tant qu’aucun arrosage n’a été enregistré. Ensuite, la prochaine échéance correspond au dernier arrosage + la fréquence. Un arrosage anticipé ou tardif décale donc le planning. Une modification de fréquence utilise la même règle ; changer la première date n’affecte pas une plante déjà arrosée.

Une échéance dépassée reste une seule tâche en attente. Les projections suivantes reprennent après l’arrosage, sans accumulation de tâches manquées. Les projections sont calculées pour le mois consulté ; elles ne sont pas des enregistrements définitifs. Les arrosages réellement effectués restent visibles dans le calendrier.

Les calculs portent sur des jours calendaires dans le fuseau de l’iPhone, y compris lors des changements d’heure. Une plante ne peut être marquée comme arrosée qu’une fois par jour. Les dates et statuts se rafraîchissent au retour dans l’application et chaque minute lorsqu’elle est ouverte.

## Données et architecture

Les plantes et leurs arrosages sont conservés dans un stockage SwiftData local, sans compte ni synchronisation CloudKit. La suppression d’une plante supprime ses arrosages associés. Les sauvegardes sont explicites : un échec annule la mutation et présente une erreur ; le formulaire reste ouvert avec les saisies conservées. Un problème d’ouverture du stockage présente une action de nouvelle tentative, sans remplacer les données par un stockage temporaire.

- `Models.swift` : plantes et arrosages, avec relation inverse et suppression en cascade.
- `WateringSchedule.swift` : calculs calendaires indépendants de l’interface et du stockage.
- `PlantStore.swift` : validation, sauvegarde, arrosage et suppression.
- `Views/` : liste, fiche, formulaire et calendrier mensuel, avec surfaces adaptées aux modes clair et sombre, Dynamic Type et libellés VoiceOver.

La grille à sept colonnes limite l’agrandissement de ses chiffres au premier niveau d’accessibilité pour garder les dates distinctes. L’agenda et les autres textes prennent en charge les tailles maximales. Les arguments de lancement destinés aux tests de présentation ne sont actifs qu’en configuration Debug.

Cette version n’inclut pas les notifications, photos, identification botanique, comptes ou publication sur l’App Store.

## Vérifications

Exécuter **⌘U** dans Xcode. Le schéma comprend les tests de planning, de persistance et les parcours d’interface. Les tests d’interface ajoutent une plante portant un nom unique, puis la suppriment ; les autres plantes ne sont pas modifiées. Les captures clair/sombre sont attachées au rapport de tests Xcode.

En ligne de commande, depuis la racine du dépôt :

```sh
xcrun simctl list devices available
xcodebuild -project Sprout.xcodeproj -scheme Sprout \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/sprout-build \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Adapter le nom du simulateur à un appareil installé. Pour compiler uniquement :

```sh
xcodebuild -project Sprout.xcodeproj -scheme Sprout \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/sprout-build CODE_SIGNING_ALLOWED=NO build
```

Les tests couvrent notamment les arrosages anticipés/tardifs, les doublons, les changements de fréquence, les frontières de mois et d’année, le 29 février, les passages à l’heure d’été/hiver, les projections, la persistance sur disque, les suppressions en cascade et le retour arrière après une erreur de sauvegarde. Les tests d’interface vérifient l’ajout, l’arrosage, la modification, le redémarrage, le calendrier et la suppression.

Vérifié le 1er octobre 2026 avec Xcode 27 : les 29 tests (26 de logique/persistance et 3 d’interface) passent sur iPhone SE (3e génération), iOS 18.2. Les parcours d’interface passent aussi sur iPhone 17, iOS 26.2. Un contrôle complémentaire sur l’iPhone SE avec la taille de texte système maximale passe, avec inspection des captures clair/sombre et du texte agrandi. Les compilations Debug et Release pour simulateur réussissent. Le runtime iOS 17 n’étant pas installé, cette version minimale n’a pas été exécutée ici.
