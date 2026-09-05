# Honey bee research

Notes gathered in 2023 when the project started, kept because they are the
source material for the simulation. Most of what is here is now encoded in
`FlowerPowerCore` and enforced by its tests: worker job ages are
`WorkerJob.ageRange`, development times are `BeeDevelopment.days(for:stage:)`,
nest sites are `HiveLocationType`, and the predator list is `Threats.swift`.

The 2023 game design that used to follow these notes — a survival and tower
defence game with a world grid, migration between squares and purchasable
queens — is **superseded**. The project is now an idle beehive simulator fed by
photographs of real flowers. See [PLAN.md](../PLAN.md) for what is actually
being built.

Where the research and the engine disagree, the engine is usually right and the
disagreement is deliberate. Two worth knowing about:

- **Larval duration.** The table below says 9 days for every kind. Real
  uncapped larval periods are about 6 days for a worker, 7 for a drone and 5
  for a queen, and the engine uses those. The flat 9 left far too little capped
  brood, which is where varroa breeds.
- **Absconding on too much honey.** The engine ties swarming to congestion and
  queen pheromone dilution rather than to honey directly, because that is the
  mechanism the honey is a proxy for.

---

## RESEARCH:

- Honey bees collect nectar and convert it to honey.
- Bees do different dances to communicate with each other.
- Most pressing threats to long-term bee survival:
    - Climate change
    - Habitat loss
    - Invasive plants and species
    - Low genetic diversity
    - Pathogens spread by commercially managed bees
    - Pesticides (houseplants, commercial farms)
- Different creatures attack bee hives:
    - Humans
    - Bears
    - Skunks
    - Raccoons
    - Mice
    - Birds
    - Wasps
    - Mites
    - Preying Mantis
    - Dragonflies
    - Cockroaches
    - Earwigs
    - Ants
    - Wax Moths
    - Crab Spiders
    - Hive Beetles
    - Killer bees
    - Honey badgers
    - Snakes
    - Opossums
    - Mountain lions
- There are three types of adult honey bees:
    - Drone:
        - All male.
        - Lifespan: 55 days.
        - Larger bees, no stinger.
        - Regularly leave the hive to find Drone Congregation Areas (DCAs) in hope of being part of a mating flight.
        - Drones main purpose is to mate, occassionally they may help cool the hive down.
        - A drone almost always dies post-coitus!
        - Otherwise, in the fall when foraging becomes scarce, worker bees kick drones out of the hive, leading to death by starvation or freezing.
    - Worker:
        - All female.
        - Lifespan: 6 weeks (summer), 5-7 months (winter)
        - Develop new roles with age:
            - Cell Cleaners (days 0-2)
            - Nurse Bees (days 2-11)
                - feed larvae royal jelly, cap cell, trim cappings
            - Mortuary (days 3-16)
                - remove dead bees, prevent disease
            - Drone Feeders (days 4-12)
            - Queen Attendants (days 7-12)
            - Nectar Concentration (days 11-20)
            - Pollen Packing (days 12-35)
            - Honeycomb Building (days 12-35)
            - Fanning (days 12 - 35)
            - Water Carriers (all days)
            - Guard Bees (days 18-21)
            - Foraging Bees (days 22-42)
                - Scout and collect nectar, pollen, water and propolis within a 5 mile radius
        - Dies when stinging something as tough as human skin.
    - Queen:
        - Lifespan: 1-2 years
        - Lays eggs that become larva:
            - Lays unfertilized eggs in drone cells (slightly bigger that worker cells)
        - Produces phermones
        - Once per lifetime with fly to a DCA where many drones will mate with her.
        - Mating with drones from different colonies increases the hive ability to resist disease.
- There are different types of food in the hive:
    - Drones and worker larva receive royal jelly for the first 2-3 days of their life.
    - After the first few days larva eat bee bread (honey and pollen mixture).
    - Honey for adult bees.
    - Too much honey will cause hive to abscond (leave in entirety) or swarm(1/2 leave with new queen). If there is no room for new queen larva then the entire hive will leave.
    - It takes 6-8 pounds of honey to make 1 pound of wax
    - Wax is needed to build comb and cap brood / honey
