# API-SECU : les prestations sociales sur API Particulier

Description fonctionnelle de la chaîne qui relie API Particulier aux
caisses de la Sécurité sociale (CNAV, SNGI, RNCPS, CNAF, MSA). Ce
document ne parle pas d'implémentation ; pour le code, partir de
`siade/app/organizers/cnav/`.

Les points marqués **À confirmer** n'ont pas été validés par le
fournisseur de données.

## Les acteurs

### API-SECU

Guichet unique de la Sécurité sociale, exploité par la CNAV (Caisse
nationale d'assurance vieillesse). C'est le seul interlocuteur d'API
Particulier pour les prestations sociales et le quotient familial : on ne parle jamais
directement à une caisse.

API-SECU ne détient aucune donnée métier. Il reçoit une identité, la
vérifie, la transforme en NIR (Numéro d'inscription au répertoire), trouve la caisse compétente, lui pose la question et relaie sa
réponse. Nos routes le nomment `dss` (`/v3/dss/...`).

### SNGI

Système national de gestion des identifiants. Référentiel des identités
de la Sécurité sociale, exploité par la CNAV.

Les caisses ne connaissent pas les identités civiles, uniquement des
NIR. Le SNGI est le seul système capable de passer d'une identité pivot
(nom de naissance, prénoms, date et lieu de naissance, sexe) à un NIR.
Sans cette conversion, aucune caisse ne peut être interrogée.

C'est ce qui explique le poids inégal des paramètres d'identification :
le nom de naissance, l'année de naissance et le lieu de naissance
suffisent souvent à trouver la personne si elle n'a pas d'homonyme, et leur absence fait chuter le
taux d'identification.

### RNCPS

Répertoire national commun de la protection sociale, exploité par la
CNAV. À partir du NIR, il indique le régime et la caisse de rattachement
de la personne.

Les caisses y remontent aussi en temps réel les droits ouverts pour les prestations. Le RNCPS
est donc à la fois l'annuaire de rattachement pour tous les endpoints et
la source de données des endpoints de statut de prestation (statut RSA,
statut AAH, prime d'activité, etc.).

### CNAF et MSA

Les caisses qui possèdent réellement les dossiers allocataires :

- CNAF : régime général, réseau des CAF ;
- MSA : régime agricole.

C'est chez elles que vivent le quotient familial, la composition
familiale et l'adresse. Le RNCPS ne porte que les droits, pas ces
données de dossier.

Les deux caisses ne fonctionnent pas au même rythme :

- la MSA recalcule en temps réel à chaque changement de situation ;
- la CAF met à jour une fois par mois, après le premier week-end du
  mois ;
- seule la CAF sert un historique du quotient familial, limité aux 24
  derniers mois.

## Le parcours d'une demande

1. L'administration appelle API Particulier avec l'identité pivot de
   l'usager, ou via FranceConnect qui fournit cette identité.
2. API Particulier contrôle la forme des paramètres et transmet à
   API-SECU.
3. **SNGI** : conversion de l'identité en NIR. Aucune correspondance :
   l'appel s'arrête sur « identité non reconnue par le fournisseur ».
   L'usager est invité à vérifier ses informations.
4. **RNCPS** : à partir du NIR, recherche du régime et de la caisse de
   rattachement. Aucun rattachement : « allocataire non référencé auprès
   des caisses éligibles ».
5. Lecture de la donnée, selon l'endpoint :
   - statut de prestation : dans le RNCPS lui-même ;
   - quotient familial : auprès de la CAF ou de la MSA, selon le
     rattachement.
6. API-SECU relaie la réponse en indiquant la caisse qui a répondu.
   API Particulier la restitue, en nommant CAF ou MSA sur le quotient
   familial.

## Les refus d'API-SECU

Un refus peut venir de trois niveaux, avec des conséquences différentes
pour l'appelant.

| Origine | Exemple | Ce que l'appelant peut faire |
|---|---|---|
| Contrôle de saisie du guichet | format du nom, commune de naissance inconnue, sexe absent, département inconnu | corriger les paramètres |
| Identification (SNGI, RNCPS) | personne introuvable, aucun rattachement | vérifier l'identité, ou fermer le dossier |
| Caisse (CAF, MSA) | dossier absent, calcul du quotient impossible, période hors historique | rien sur l'identité ; changer la période ou réessayer plus tard |

Cas particulier du quotient familial : la CAF ne sert que 24 mois
d'historique. Une période plus ancienne est refusée par la caisse et
restituée comme « période refusée par le fournisseur de données », pas
comme une erreur d'identité.

## Endpoints concernés

Tous les endpoints ci-dessous passent par API-SECU. Chacun existe en
deux modalités d'appel, `/identite` (identité pivot) et
`/france_connect`.

### Données CAF / MSA

| Prestation | Route v3 |
|---|---|
| Quotient familial et composition familiale | `/v3/dss/quotient_familial/{identite,france_connect}` |
| Participation familiale EAJE (prestation de service unique) | `/v3/dss/participation_familiale_eaje/{identite,france_connect}`|

### Données RNCPS

| Prestation | Route v3 |
|---|---|
| Revenu de solidarité active | `/v3/dss/revenu_solidarite_active/{identite,france_connect}` |
| Prime d'activité | `/v3/dss/prime_activite/{identite,france_connect}` |
| Allocation aux adultes handicapés | `/v3/dss/allocation_adulte_handicape/{identite,france_connect}` |
| Allocation de soutien familial | `/v3/dss/allocation_soutien_familial/{identite,france_connect}` |
| Allocation de rentrée scolaire | `/v3/dss/allocation_rentree_scolaire/{identite,france_connect}` |
| Allocation d'éducation de l'enfant handicapé | `/v3/dss/allocation_enfant_handicape/{identite,france_connect}` |
| Complémentaire santé solidaire | `/v3/dss/complementaire_sante_solidaire/{identite,france_connect}` |

**À confirmer** : la source de la complémentaire santé solidaire. Les
fiches publiques la présentent comme issue du RNCPS, et l'historique du
projet la traite comme le cas où le RNCPS répond directement en tant
que régime. La C2S étant une prestation de l'Assurance maladie et non
des caisses d'allocations familiales, cette origine reste à valider
avec la CNAV.

**À confirmer** : le RNCPS comme source directe des statuts de
prestation. Les fiches publiques l'affirment ; la CNAV ne l'a pas
formellement confirmé.
