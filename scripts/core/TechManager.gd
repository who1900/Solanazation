extends RefCounted
class_name TechManager
## TechManager — tech tree (archiotech). Researched in cities.

var researched: Dictionary = {}  # tech_id -> true
var current: String = ""         # tech being researched
var points: int = 0              # accumulated research points


func can_research(tech_id: String, resources: Dictionary) -> bool:
	var td: Dictionary = Data.TECHS[tech_id]
	return not researched.has(tech_id) and resources.sol >= int(td.sol_cost)


## Start research (spends $SOL).
func start_research(tech_id: String, resources: Dictionary) -> bool:
	if researched.has(tech_id):
		return false
	var td: Dictionary = Data.TECHS[tech_id]
	if resources.sol < int(td.sol_cost):
		return false
	resources.sol -= int(td.sol_cost)
	current = tech_id
	return true


## Tech points per turn from a city (archio-archive +50%).
func city_tech_points(city: City) -> int:
	var base := city.population
	if city.has_building("archio_archive"):
		base = int(round(base * 1.5))
	return maxi(base, 1)


## Research progress; on completion — unlocks.
func add_points(amount: int) -> Dictionary:
	if current == "" or researched.has(current):
		return {}
	points += amount
	var cost := research_cost(current)
	if points < cost:
		return {}
	points = 0
	researched[current] = true
	var td: Dictionary = Data.TECHS[current]
	current = ""
	return {
		"tech": td.name,
		"units": td.units,
		"buildings": td.buildings,
	}


func research_cost(tech_id: String) -> int:
	var td: Dictionary = Data.TECHS[tech_id]
	# base progress: 20 points + $SOL cost as multiplier
	return 20 + int(td.sol_cost)


func is_researched(tech_id: String) -> bool:
	return researched.has(tech_id)


## Researchable techs (not yet researched).
func available() -> Array:
	var result: Array = []
	for t in Data.TECHS:
		if not researched.has(t):
			result.append(t)
	return result


## Highest era reached by researched techs.
func current_era() -> int:
	var era := 1
	for t in researched:
		era = maxi(era, int(Data.TECHS[t].era))
	return era


## Techs whose requirements are met (available to research).
func researchable(era: int = -1) -> Array:
	var result: Array = []
	for t in Data.TECHS:
		if researched.has(t):
			continue
		var td: Dictionary = Data.TECHS[t]
		var ok := true
		for req in td.requires:
			if not researched.has(req):
				ok = false
				break
		if ok and (era < 0 or int(td.era) <= era + 1):
			result.append(t)
	return result
