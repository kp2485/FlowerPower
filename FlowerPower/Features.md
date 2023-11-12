#  Flower Power Features

- Open Source Survival / Tower Defense game using SwiftUI

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

## FEATURES:

- Each game starts with a queen, 2 drones and 3 workers.
- The queen must first find a hive location and direct the workers to build a hive.
- Ultimate goal is to grow and protect the hive, especially the queen.
- 2 game phases:
    - Growth phase (grow the hive, expand territory)
    - Defense phase (defend against onslaught of creatures)
- Resources:
    - Nectar (flowers)
    - Pollen (flowers)
    - Water
    - Propolis (trees)
    - Wax (adult bees)
    - Royal jelly (nurse worker bees)
- Jobs:
    - Send gather bees to specific resources.
    - 
- The temperature and humidity of the hive must be maintained by workers.
- Additional queen bees can be unlocked through play or quickly through payment.
- Queen lays eggs, directs workers and sends out worker bees to attack threats.
- Some insects will help:
    - Carpenter bee
    - Bumblebee
    - Butterflies
- Bee development goes as follows (Default number of days, days after Upgrade 1, Upgrade 2):
            Egg         Larva       Pupa         
    QUEEN   (3,2,1)     (9, 7, 4)   (15, 13, 10)
    WORKER  (3,2,1)     (9, 7, 4)   (20, 15, 10)
    DRONE   (3,2,1)     (9, 7, 4)   (23, 17, 10)
- Possible hive locations (cavity dwellers, mostly above ground):
    - living tree cavities
    - inside dead fallen tree
    - under tree branches
    - cliffs or rock outcroppings
    - caves
    - inside walls
    - attached to human structures
    - termite mound
    - underground animal burrow
    - nestbox

## INTERFACE: 

- Main views:
    - MapView (includes player hive, other hives, DCAs and all nearby resources/creatures)
        - tap on entities (flowers, trees, houses, farms, etc...) to send bees
        - map starts undiscovered and a fog of war exists after bees depart an area
        - sandbox which extends beyond what is displayed on the screen
        - similar to Maps, there is a compass button which will center the map on the hive with the first tap and display hive details with a second tap
    - HiveDefenseView (tower defense for the hive)
    - HiveInteriorView (hex cells for each larva/bee)
        - entrance where resources are deposited
        - tap cell to see details of inhabitant, cleanliness and any diseases present
        - plus button to build worker/drone/queen/resource storage cell
        - empty cells from dead bees can be reused after cleaning
    - HiveHealthView (list of all resources and jobs and slider for number of bees assigned to each job)
        - Larva:
        - Drones:
        - Workers:
        - Queen:
        - Cleanliness:
        - Diseases:


