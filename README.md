# Scrolls of the Automaton Enchanter

Hark, Outlander, for you have uncovered a tome of great power. Within these digital pages lie two enchantments of Dwemer-like ingenuity, forged to bring order to the chaotic process of customizing the visions one experiences through the Seeing-Glass of OpenMW.

These scripts were scribed to automate the selection and ordering of arcane scrolls (`.esp`, `.omwaddon`) and enchanted textures (`Textures`, `Meshes`) for a private collection. They are a chronicle of one enchanter's journey.

### Scribe's Note on Provenance

Be warned, traveler. These enchantments are of a personal nature, tuned to the specific ley-lines and astral configurations of their creator's domain (their PC). The paths and incantations herein may not suit your own realm without alteration. This is a private grimoire, not a public work for the Mages Guild. As such, no succor or support shall be provided should the enchantments go awry. Proceed with scholarly caution.

### The Primary Enchantment: `openmw-config-automator.ps1`

This is the master ritual. When invoked, it will perform a complex series of rites to organize your collected works and prepare them for the Seeing-Glass.

**Rites of Invocation:**

* **The Rite of Purity:** It first purifies the names of your collected works, stripping them of clumsy markings to prevent cosmic misalignments.
* **The Rite of Divination:** The script then scries your collection, discerning the nature of each artifact. Should it find a work with multiple potential forms (e.g., "00 Core," "01 Patches"), it will seek your counsel. Your choices are remembered in a 'mod_choices' folio for future rites.
* **The Rite of Scribing:** A `momw-customizations.toml` scroll is scribed, listing the precise order and location of your chosen artifacts.
* **The Rite of Configuration:** The grand `momw-configurator` automaton is summoned to imbue your primary Seeing-Glass configuration (`openmw.cfg`) with the new order.
* **The Rite of Final Adjustment:** A final, subtle enchantment is cast upon the `openmw.cfg` scroll to ensure a specific artifact (`LuaMultiMark.omwaddon`) is placed in its proper sequence.

### The Lesser Enchantment: `save-to-git.ps1`

This is a familiar, a loyal servant summoned by the primary enchantment. Its sole purpose is to create a perfect, incorporeal copy of these works in the Aetherial Archive known as GitHub. It ensures that should disaster strike, your knowledge is not lost to the ages. It is intelligent, and will only perform its task when it senses a change in the weave, or when a full day has passed.