# Balance baseline: Small / Pangaea

Deterministic matrix: 24 matches, 12 with three factions and 12 with four,
maximum 300 turns. The runner is `tests/balance_telemetry.gd`.

## Accepted bootstrap slice

Before the fix, 17/24 matches had no winner at turn 300 and 22/24 left the AI
at Era 0. Most starting cities had no positive local Energy, so they could not
gather resources or build the turbine needed to escape the blackout.

The Genesis Node now supplies the minimum 3 Energy needed to keep the existing
early AI build order operational until its Steam Turbine comes online. Monopoly
also requires at least 100 total network SOL and two positive treasuries; the
existing strict greater-than-80% share and ten-turn duration are unchanged.

After the slice, 20/24 matches resolve by turn 300: 11 Domination, 9 Monopoly,
and 4 unresolved. Surviving AI factions develop real economies and reach Era I
or II. The bounded acceptance matrix resolves 8/10 matches by turn 200, has no
Monopoly before turn 40, and reproduces gameplay state for the same seed.

## Deferred P1 findings

These are measured issues, intentionally not mixed into the bootstrap fix:

- diplomacy eventually leaves every faction pair permanently at war;
- several seeds churn city ownership (13–37 captures) without a decisive end;
- an inactive player can win Monopoly by hoarding while AI treasuries spend;
- AI research priorities stop at Era II;
- late-game Biomass, Energy, Scrap, and SOL stockpiles have weak sinks;
- active late-game AI turns need a separate performance pass.

## Strategic Arc v1

Monopoly now certifies cumulative network production rather than current
spendable treasuries. Only positive city/validator output enters the ledger;
gifts, trades, terminal and lair windfalls, and combat loot remain treasury
transactions. A 24-match idle-human run produced zero Human wins, replacing the
three passive Human Monopoly wins in the previous baseline. Certification still
requires two producing factions, 100 cumulative network SOL, a strict share over
80%, and ten consecutive qualifying turns.

Pairwise war exhaustion uses the existing deterministic relation pairs. The
accepted conservative trial uses 30 conflict turns, +4 exhaustion per city
capture, and a six-turn ceasefire before the pair can declare again. Captured
cities expose an absolute three-turn `SECURED` expiry applied identically to all
owners. The same matrix resolved 18/24 matches (15 Domination, 3 Monopoly),
reduced capture churn from the documented 37 maximum to 12, left no unresolved
match with every pair at war, and produced 11 Era-IV factions. Runtime was 115.2
seconds because six matches reached the 300-turn cap.

One bounded pacing trial extended conflicts to 36 turns and shortened ceasefires
to five. It resolved 20/24 in 84.0 seconds, but maximum capture churn returned to
26 and an unresolved match again ended with every pair at war. That trial was
rejected: faster resolution does not count as progress if it restores two of the
P1 failures this slice exists to remove. Reaching 20/24 without recurring war
churn remains the next balance constraint, not a reason to hide a second tuning
change in this package.

A final targeted trial kept the 36/5 diplomacy timing but extended absolute city
stabilization from three turns to five. It also resolved 20/24 and improved
runtime to 79.6 seconds, but still reached 17 captures in one match and retained
one unresolved all-pairs-war cap. It therefore failed the explicit maximum-14
churn and zero-permanent-all-war gates and was rejected. The conservative 30/6/3
configuration above remains the measured choice.

All three AI agendas now contain legal prerequisite-respecting priorities for
all 13 current technologies and can reach Era IV without discounts.
