# Habito

**AAC2-Habito** is an iOS app that turns everyday tasks into a living garden. Parents assign tasks from their phone; the child completes them by feeding apples to a hungry caterpillar. Every seven perfect days, the caterpillar turns into a butterfly that joins the child's collection.

This repository contains the **iOS frontend** (SwiftUI). The backend lives in a separate repository: [BokijonovS/habito](https://github.com/BokijonovS/habito).

<p align="center">
<img width="1274" height="714" alt="habito scren" src="https://github.com/user-attachments/assets/0f565554-42e4-4ef2-8a12-ddd04d736bac" />
</p>

---

## The idea

Children with a full day of tasks done deserve more than a checkmark. In Habito:

- Each task is an **apple blossom** on a tree.
- "I did it!" marks the task done on the server (and notifies the parent) — the blossom turns into a **ripe apple**.
- The child pulls the apple off the tree and **feeds it to the caterpillar**.
- **Seven perfect days** (every task eaten) grow the caterpillar into a **butterfly**.
- Butterflies join **My Butterflies**, a collection from common to legendary. The child can heart favourites, and those favourites come to life in the **Garden**.

<p align="center">
  <img width="1262" height="710" alt="screen" src="https://github.com/user-attachments/assets/b85e00cf-cf43-464f-8a30-a208cc8dec47" />
</p>

---

## Screens

<p align="center">
  <img width="1266" height="713" alt="ipad" src="https://github.com/user-attachments/assets/8b61f0f8-7968-42ff-938e-c4e5ebdd59fd" />
</p>

| Screen | What it does |
|---|---|
| **Join your family** | Six-box room code entry (with error shake). The code comes from the parent's phone. |
| **Tree** | The main screen: hand-drawn tree, one apple per task, caterpillar on a leaf, progress bar. Tap a blossom to read the task aloud; drag a ripe apple to the caterpillar to feed it; drop it anywhere else and it falls away and regrows. |
| **Garden** (beta) | Favourite butterflies flutter between two flower beds, land on flowers, rest with slow wing beats, and fly off. A two-page picture guide shows how it works. |
| **Butterflies** | Collection grid of every butterfly kind (locked ones are grey with a padlock). Tap a found butterfly for its name, Latin name, rarity and a fun fact. Heart it to send it to the Garden. |
| **Butterfly reveal** | Seven perfect days trigger a white flash and a spinning-ray reveal of the new butterfly. |

---

## Design highlights

- **Hand-drawn assets** — tree, caterpillar, butterflies, leaves, petals — all original artwork.
- **Motion everywhere, but gentle**: apples swing like pendulums when the phone is shaken; the caterpillar wobbles, gets dizzy (spiral eyes) and squashes happily when it eats.
- **Accessibility first**: `accessibilityReduceMotion` is respected throughout (cross-fades instead of flashes, still butterflies, no shakes), VoiceOver labels on every interactive element, and "Read aloud" uses `AVSpeechSynthesizer` for children who cannot read yet.
- **iPad support**: the whole scene is laid out in design points and scales to fill either orientation (see `TreeLayout`). On iPad, rubbing a finger back and forth replaces the phone shake.
- **Local game state**: perfect days, butterflies and favourites are persisted in `UserDefaults`; the child token lives in the Keychain.

<p align="center">
  <img width="1268" height="711" alt="caterpillar" src="https://github.com/user-attachments/assets/87ffa484-26e3-44c0-84e7-b52659699eed" />
</p>

---

## 🏗 Architecture

Key separations:

- **`ChildTreeModel`** (`@Observable`, `@MainActor`) owns all server state and never sees animation state. Views own their own transient animation state (`carried`, `falling`, `shake`, …).
- **`ChildGame`** is the local game engine: it counts perfect days, decides when a butterfly is ready, and stores the collection.
- **`GardenFlock`** plans butterfly flights ahead in short legs (fly → glide → rest → take off), booking flowers so two butterflies never land on the same one.

---

## Getting started

### Requirements

- Xcode 16+ / iOS 17+ (uses `@Observable`, `keyframeAnimator`, `phaseAnimator`)
- The backend running or reachable (see below)

### Run

1. Clone this repository and open `Habito.xcodeproj`.
2. Start the backend from [BokijonovS/habito](https://github.com/BokijonovS/habito) and point `HabitoAPI` at its base URL.
3. Build and run on a simulator or device.

### Test the join flow

The parent app generates a six-character room code; enter it on the child's device. For presentations, `ChildGame.startNewChild()` seeds the child with 2 butterflies and 6 perfect days, so one perfect day demonstrates the full butterfly reveal.

---

## 🧪 Testing

- UI tests can simulate a shake via the `HABITO_TEST_SHAKE` environment variable (`debugShake` button, debug builds only).
- Accessibility identifiers are provided throughout (`caterpillar`, `garden`, `roomCodeBoxes`, …) for automated UI testing.
- The frontend developer is responsible for the test suite.

---

## 👥 The team

| Name | Role |
|---|---|
| **Stefano Emanuele Aldanese** ([@StefanoAldanese](https://github.com/StefanoAldanese)) | Developer — frontend & testing |
| **Sanatbek Bokijonov** ([@BokijonovS](https://github.com/BokijonovS)) | Developer — backend & frontend |
| **Sanaz Asadi** | Research & Keynote |
| **Weerapurage Nipunika Sanduni Fernando** | Keynote |
| **Alessandra Ambrosio** | Artist — hand-drawn assets |

---

## 🔗 Links

- Backend: [github.com/BokijonovS/habito](https://github.com/BokijonovS/habito)
- Built for the **AAC2** course project.

---

*Habito — Behind every growing child is someone who believes in them*
```
