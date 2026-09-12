extends RefCounted
class_name EducationData
## Offline educational copy. Gameplay rules remain in Data.gd.

const ERA_NAMES := {1: "Foundation", 2: "Composition", 3: "Scale", 4: "Production"}
const BRANCH_NAMES := {
	"validator": "Validator Engineering",
	"program": "Program Architecture",
	"transaction": "Transaction Economy",
}

const TECHS := {
	"steam_synthesis": {
		"card_effect": "Steam Cruiser + Turbine · Ruins +1 Scrap",
		"game_effect": "Unlocks Steam Cruiser and Steam Turbine. Ruins yield +1 Scrap.",
		"real_solana": "Proof of History provides a verifiable source of time and ordering. Time is divided into slots, and each slot has a designated leader that may produce a block. Validators still vote on forks, so Proof of History is not the complete consensus mechanism and a scheduled slot does not guarantee a block.",
		"fiction": "The cruiser, turbine, and extra Scrap are wasteland progression rewards. They are an analogy for ordered work, not effects produced by Proof of History on Solana.",
		"terms": ["Proof of History & Slot", "Validator"],
		"source_urls": ["https://docs.anza.xyz/implemented-proposals/tower-bft"],
	},
	"primitive_coding": {
		"card_effect": "Net Broker · Diplomacy + trade",
		"game_effect": "Unlocks Net Broker, diplomacy, and the fictional $SOL trade action.",
		"real_solana": "An account is Solana's fundamental state unit, addressed by a 32-byte key. It stores lamports, data, an owner, an executable flag, and rent metadata. Runtime ownership rules determine which program may modify account data or debit lamports; an account is not simply a user profile or database row.",
		"fiction": "Net Brokers and diplomatic trade represent learning to address and authorize shared state. Hacking and faction trade are fictional strategy systems, not account features.",
		"terms": ["Account", "Program"],
		"source_urls": ["https://solana.com/docs/core/accounts"],
	},
	"hydroponics": {
		"card_effect": "Biomass Purifier",
		"game_effect": "Unlocks Biomass Purifier for the survival economy.",
		"real_solana": "A Solana transaction contains signatures, a recent blockhash, account addresses, and one or more instructions. Its instructions execute atomically: all succeed or state changes revert, while transaction fees can still be charged on failure. Fees include a base fee and may include an optional compute-unit priority fee.",
		"fiction": "Purifying biomass is a survival analogy for validating a complete operation before accepting its result. Solana transactions do not create food or remove radiation.",
		"terms": ["Transaction & Fee", "Commitment"],
		"source_urls": ["https://solana.com/docs/core/transactions", "https://solana.com/docs/core/fees"],
	},
	"atomic_reactor": {
		"card_effect": "+10 Energy · Nuclear Plant upgrade",
		"game_effect": "Adds +10 Energy per turn and enables the Nuclear Plant upgrade.",
		"real_solana": "Validators replay ledger entries and send signed votes for the forks they consider valid. Tower BFT uses stake-weighted fork choice and increasing vote lockouts to make rollback progressively more costly. Stake affects consensus weight, but it does not promise a fixed reward, uptime, transaction rate, or return for a delegator.",
		"fiction": "The reactor and flat Energy bonus visualize the operating cost of consensus. Real validators consume infrastructure resources, but Tower BFT does not generate game energy.",
		"terms": ["Validator", "Tower BFT", "Proof of History & Slot"],
		"source_urls": ["https://docs.anza.xyz/implemented-proposals/tower-bft", "https://solana.com/validators"],
	},
	"block_encryption": {
		"card_effect": "Hack defense · Validators + Exchange",
		"game_effect": "Reduces enemy hack success by 25% and unlocks Relic Validator and SOL Exchange.",
		"real_solana": "Solana programs contain executable sBPF bytecode but keep mutable state in separate data accounts. A Program Derived Address is deterministically derived from a program ID and seeds, has no private key, and can be authorized by its owning program through the runtime's invoke_signed mechanism during a cross-program call.",
		"fiction": "Hack defense and validator buildings are game abstractions for explicit ownership and authority checks. PDAs are not encryption and do not make a program automatically secure.",
		"terms": ["Program", "Program Derived Address"],
		"source_urls": ["https://solana.com/docs/core/programs", "https://solana.com/docs/core/pda"],
	},
	"radiation_engineering": {
		"card_effect": "Swamps no longer reduce Biomass",
		"game_effect": "Removes radiation penalties from the faction's survival economy.",
		"real_solana": "A Cross-Program Invocation lets one program call an instruction of another program while the runtime enforces signer and writable privileges. SPL Token programs define mints, token accounts, authorities, transfers, minting, and burning. A token operation must satisfy those authority rules; creating a mint does not create market value or liquidity.",
		"fiction": "Radiation immunity represents safe composition across hostile systems. CPI and SPL Tokens do not protect people from environmental hazards or guarantee valuable assets.",
		"terms": ["Cross-Program Invocation", "SPL Token"],
		"source_urls": ["https://solana.com/docs/core/cpi", "https://solana.com/docs/tokens/basics"],
	},
	"quantum_computing": {
		"card_effect": "Fusion Plant upgrade",
		"game_effect": "Marks the Scale era and enables the Fusion Plant upgrade.",
		"real_solana": "Turbine propagates block data by splitting it into batches and relaying them through peers. Stake-weighted Quality of Service can reserve leader ingress capacity for traffic forwarded through trusted staked validator and RPC relationships as Sybil resistance. It is an optional traffic policy, not a guarantee that a transaction lands.",
		"fiction": "Fusion power represents a stronger relay network. The game's Energy upgrade is not a throughput, finality, or inclusion promise made by Turbine or stake-weighted QoS.",
		"terms": ["Turbine", "Stake-weighted QoS", "Validator"],
		"source_urls": ["https://docs.anza.xyz/clusters/", "https://solana.com/developers/guides/advanced/stake-weighted-qos"],
	},
	"smart_contracts": {
		"card_effect": "Auto-Factory · Energy → SOL",
		"game_effect": "Unlocks Auto-Factory and converts each 10 surplus Energy into 1 fictional $SOL.",
		"real_solana": "Transactions declare the accounts they read and write. Work touching independent account sets can be scheduled in parallel, while conflicting writable accounts must be serialized. Compute units meter execution work and help price priority, but they are not electricity. A shared hot account can remain a bottleneck despite otherwise parallel hardware.",
		"fiction": "The auto-factory and Energy conversion model efficient parallel production. Solana compute units cannot be converted into SOL, and a program does not guarantee profit.",
		"terms": ["Parallel Runtime & Compute Units", "Transaction & Fee", "Program"],
		"source_urls": ["https://solana.com/docs/core/transactions/transaction-pipeline", "https://solana.com/docs/core/fees"],
	},
	"cyber_implants": {
		"card_effect": "Heavy Mech + Forge · Infantry +1 move",
		"game_effect": "Unlocks Heavy Mech and Cyber Forge. Infantry gains +1 movement.",
		"real_solana": "Versioned v0 transactions can replace inline 32-byte account addresses with 1-byte indexes into an onchain Address Lookup Table. This allows a transaction message to reference more accounts within its packet budget. Validators resolve those indexes before execution. ALTs reduce address bytes; they do not add compute, increase unit speed, or guarantee confirmation.",
		"fiction": "Faster infantry represents fitting more references into one coordinated order. The movement bonus is fiction and not a property of v0 messages or ALTs.",
		"terms": ["V0 Transaction & Address Lookup Table", "Commitment"],
		"source_urls": ["https://solana.com/docs/core/transactions/versioned-transactions", "https://solana.com/developers/guides/advanced/lookup-tables"],
	},
	"satellite_uplink": {
		"card_effect": "Reveal validators · Uplink objectives",
		"game_effect": "Reveals enemy validator locations and unlocks late-game uplink objectives.",
		"real_solana": "RPC nodes answer blockchain queries and submit transactions, but normally do not vote in consensus. Clients should distinguish processed, confirmed, and finalized commitment instead of treating every observed transaction as final. Monitoring multiple healthy sources improves operational visibility, yet an RPC response alone is not a consensus guarantee.",
		"fiction": "The satellite reveals strategic buildings as an analogy for observability. Real RPC access does not reveal private enemy locations or remove fog of war.",
		"terms": ["Commitment", "Validator"],
		"source_urls": ["https://docs.anza.xyz/what-is-an-rpc-node", "https://solana.com/docs/rpc"],
	},
	"global_consensus": {
		"card_effect": "Global Server · SOL output +50%",
		"game_effect": "Unlocks the Consensus Council and increases fictional $SOL output.",
		"real_solana": "Bubblegum V2 compressed NFTs store compact Merkle-tree state rather than one conventional account per asset. Clients use proofs and indexers to locate and update assets, trading lower onchain storage for proof, indexing, and data-availability dependencies. The Merkle root supports verification but does not make ownership or metadata private. This entry does not describe every system called state compression.",
		"fiction": "The council and income bonus represent coordinating more settlements with compact asset state. Bubblegum V2 does not create consensus votes, governance authority, privacy, or revenue.",
		"terms": ["State Compression", "Account"],
		"source_urls": ["https://developers.metaplex.com/smart-contracts/bubblegum-v2/sdk/javascript", "https://developers.metaplex.com/bubblegum-v2/concurrent-merkle-trees"],
	},
	"terraforming": {
		"card_effect": "Powered wasteland → +1 Biomass",
		"game_effect": "Wasteland tiles near powered cities yield +1 Biomass.",
		"real_solana": "Token Extensions add optional behaviors to mints and token accounts. Applications must detect present extensions and handle them correctly or reject unsupported assets. A Jito bundle contains up to five signed transactions that execute in order and all-or-nothing if the bundle lands. Its tip is separate from Solana's compute-unit priority fee; receipt or a higher tip does not guarantee landing.",
		"fiction": "Terraforming represents choosing asset rules and coordinated transactions to reshape an economy. Neither Token Extensions nor Jito bundles restore land, create food, guarantee execution, or guarantee token value.",
		"terms": ["Token Extensions", "Jito Bundle", "Transaction & Fee"],
		"source_urls": ["https://solana.com/developers/guides/token-extensions/getting-started", "https://docs.jito.wtf/lowlatencytxnsend/"],
	},
	"firedancer": {
		"card_effect": "No outage events · Energy ×1.5",
		"game_effect": "Prevents fictional outage events and multiplies the game's Energy total by 1.5.",
		"real_solana": "Independent validator implementations reduce common-mode software and supply-chain risk. Agave is actively developed by Anza. Frankendancer combines Firedancer networking and block production with Agave execution and consensus and is available on mainnet-beta; the full from-scratch Firedancer client is not yet released for production according to its official repository.",
		"fiction": "Permanent outage immunity and extra Energy are explicit strategy abstractions. Client diversity reduces correlated implementation risk; it cannot promise that a real network never experiences outages.",
		"terms": ["Client Diversity", "Validator"],
		"source_urls": ["https://docs.anza.xyz/", "https://github.com/firedancer-io/firedancer"],
	},
}

const GLOSSARY := {
	"account": {"name": "Account", "definition": "The addressed unit that stores lamports, data, ownership, and other runtime metadata.", "source": "https://solana.com/docs/core/accounts"},
	"program": {"name": "Program", "definition": "Executable sBPF code; mutable program state lives in separate data accounts.", "source": "https://solana.com/docs/core/programs"},
	"transaction_fee": {"name": "Transaction & Fee", "definition": "An atomic set of instructions authorized by signatures; fees may still be charged when execution fails.", "source": "https://solana.com/docs/core/transactions"},
	"poh_slot": {"name": "Proof of History & Slot", "definition": "Verifiable time and ordering divided into leader slots; PoH is not the whole consensus mechanism.", "source": "https://docs.anza.xyz/implemented-proposals/tower-bft"},
	"tower": {"name": "Tower BFT", "definition": "The current vote-lockout and stake-weighted fork-choice design documented for Agave.", "source": "https://docs.anza.xyz/implemented-proposals/tower-bft"},
	"validator": {"name": "Validator", "definition": "A node that replays the ledger, may produce blocks as leader, and votes in consensus.", "source": "https://docs.anza.xyz/validator/anatomy"},
	"pda": {"name": "Program Derived Address", "definition": "A deterministic off-curve address with no private key; its program can authorize it through the runtime.", "source": "https://solana.com/docs/core/pda"},
	"cpi": {"name": "Cross-Program Invocation", "definition": "One program invoking another program's instruction with runtime-enforced privileges.", "source": "https://solana.com/docs/core/cpi"},
	"spl": {"name": "SPL Token", "definition": "A token model built from mints, token accounts, authorities, and Token Program instructions.", "source": "https://solana.com/docs/tokens/basics"},
	"parallel_compute": {"name": "Parallel Runtime & Compute Units", "definition": "Non-conflicting account access can run in parallel; compute units meter execution work, not electricity.", "source": "https://solana.com/docs/core/transactions/transaction-pipeline"},
	"v0_alt": {"name": "V0 Transaction & Address Lookup Table", "definition": "A versioned message can reference onchain address tables through compact indexes to save packet space.", "source": "https://solana.com/docs/core/transactions/versioned-transactions"},
	"commitment": {"name": "Commitment", "definition": "The requested confidence level for observed ledger state, commonly processed, confirmed, or finalized.", "source": "https://solana.com/docs/rpc"},
	"turbine": {"name": "Turbine", "definition": "The block propagation technique that splits data into batches and relays them through validator peers.", "source": "https://docs.anza.xyz/clusters/"},
	"qos": {"name": "Stake-weighted QoS", "definition": "Optional stake-aware TPU ingress allocation used as Sybil resistance; it does not guarantee landing.", "source": "https://solana.com/developers/guides/advanced/stake-weighted-qos"},
	"client_diversity": {"name": "Client Diversity", "definition": "Multiple independently implemented validator clients reduce correlated implementation and dependency risk.", "source": "https://github.com/firedancer-io/firedancer"},
	"compression": {"name": "State Compression", "definition": "Bubblegum V2 cNFTs use Merkle trees, proofs, and indexers to reduce per-asset onchain state; this is not privacy.", "source": "https://developers.metaplex.com/bubblegum-v2/concurrent-merkle-trees"},
	"token_extensions": {"name": "Token Extensions", "definition": "Optional Token-2022 mint and token-account behaviors that applications must handle or explicitly reject.", "source": "https://solana.com/developers/guides/token-extensions/getting-started"},
	"jito_bundle": {"name": "Jito Bundle", "definition": "Up to five signed transactions execute in order and all-or-nothing if landed; its tip is separate from the compute-unit priority fee, and receipt or a higher tip does not guarantee landing.", "source": "https://docs.jito.wtf/lowlatencytxnsend/"},
}


static func official_source_urls() -> Array[String]:
	var result: Array[String] = []
	for tech_id in TECHS:
		for source_url in TECHS[tech_id].source_urls:
			var url := str(source_url)
			if not result.has(url):
				result.append(url)
	for entry_id in GLOSSARY:
		var url := str(GLOSSARY[entry_id].source)
		if not result.has(url):
			result.append(url)
	return result


static func is_official_source_url(url: String) -> bool:
	return url.begins_with("https://") and official_source_urls().has(url)
