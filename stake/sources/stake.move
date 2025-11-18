module lumio::stake {
    use std::bcs;
    use std::hash::sha3_256;
    use std::signer;
    use std::string::String;
    use aptos_std::table_with_length;
    use aptos_std::table_with_length::TableWithLength;

    use aptos_framework::account;
    use aptos_framework::account::SignerCapability;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::Metadata;
    use aptos_framework::object::Object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::util;

    use lumio::duration::{Self, assert_lumio_duration, selected};

    // Errors.

    /// When signer is not an owner.
    const ERR_SIGNER_NOT_OWNER: u64 = 100;
    /// When staking module is not initialized.
    const ERR_NOT_INITIALIZED: u64 = 101;
    /// When stake with same index address already exists. Should be unreachable.
    const ERR_STAKE_INDEX_ADDR_ALRD_EXISTS: u64 = 102;
    /// When user has no stake with specified id.
    const ERR_STAKE_DOESNT_EXIST: u64 = 103;

    // Resources.

    /// Stores user stake details.
    struct Stake has key {
        // Stake owner address.
        owner: address,
        // Address of receiver on Lumio chain.
        in_behalf_of: address,
        // Stake index.
        id: u64,
        // Staked amount.
        amount: u64,
        // Stake duration.
        duration: String,
        // Stake timestamp.
        lock_date: u64,
        // Unlock timestamp.
        unlock_date: u64
    }

    /// Lumio staking module state.
    struct StakingState has key {
        // Lumio FungibleAsset metadata.
        lumio_metadata: Object<Metadata>,
        // Account to hold staked asset.
        assets_holder: SignerCapability,

        // Current total locked value.
        total_locked: u64,
        // Current total unlocked value.
        total_unlocked: u64,
        // Table to store users stakes.
        // Mapps hash(user_addr + stake_id) => Stake.
        stakes: TableWithLength<address, Stake>,

        // Table to store user stakes count.
        // Mapps user_addr => stakes_count.
        users: TableWithLength<address, u64>
    }

    // Module initialization.

    public entry fun init(
        lumio_acc: &signer, lumio_metadata: Object<Metadata>
    ) {
        // Check is signed by owner.
        assert!(signer::address_of(lumio_acc) == @lumio, ERR_SIGNER_NOT_OWNER);

        // Create asset holder account.
        let (_, signer_cap) =
            account::create_resource_account(lumio_acc, b"lumio-stake-assets-holder");
        let assets_holder_addr = account::get_signer_capability_address(&signer_cap);

        // Create module initial state.
        let state = StakingState {
            lumio_metadata,
            assets_holder: signer_cap,
            total_locked: 0,
            total_unlocked: 0,
            stakes: table_with_length::new(),
            users: table_with_length::new()
        };
        move_to(lumio_acc, state);

        // Emit initialized event.
        event::emit(LumioStakingInitializedEvent { lumio_metadata, assets_holder_addr });
    }

    // Staking logic.

    public entry fun stake<Duration>(
        user_acc: &signer, amount: u64, in_behalf_of: address
    ) acquires StakingState {
        // Check `Duration` is correct generic.
        assert_lumio_duration<Duration>();
        // Check module initialized.
        assert!(is_initialized(), ERR_NOT_INITIALIZED);

        let state = borrow_global_mut<StakingState>(@lumio);
        let lumio_metadata = state.lumio_metadata;

        // Transfer assets to holder.
        let holder_addr = account::get_signer_capability_address(&state.assets_holder);
        primary_fungible_store::transfer(user_acc, lumio_metadata, holder_addr, amount);

        // Add user stakes count if needed.
        let user_addr = signer::address_of(user_acc);
        if (!state.users.contains(user_addr)) {
            state.users.upsert(user_addr, 0);
        };

        // Get current user stake id.
        let current_stake_count = state.users.borrow_mut(user_addr);
        let current_stake_id = *current_stake_count + 1;

        // Increase stake counter.
        *current_stake_count = *current_stake_count + 1;

        // Create stake data.
        let now = timestamp::now_seconds();
        let unlock_date = now + duration::seconds<Duration>();
        let stake = Stake {
            owner: user_addr,
            in_behalf_of,
            id: current_stake_id,
            amount,
            duration: selected<Duration>(),
            lock_date: now,
            unlock_date
        };

        // Create and check stake index address.
        let stake_index_addr = create_stake_index_address(user_addr, current_stake_id);
        assert!(
            !state.stakes.contains(stake_index_addr),
            ERR_STAKE_INDEX_ADDR_ALRD_EXISTS
        );

        // Save stake and increase total locked value.
        state.stakes.add(stake_index_addr, stake);
        state.total_locked = state.total_locked + amount;

        // Emit stake event.
        event::emit(
            StakeEvent<Duration> {
                user_addr,
                in_behalf_of,
                id: current_stake_id,
                amount,
                unlock_date
            }
        );
    }

    // View functions.

    #[view]
    ///
    public fun is_initialized(): bool {
        exists<StakingState>(@lumio)
    }

    #[view]
    ///
    public fun get_total_locked(): u64 acquires StakingState {
        borrow_global<StakingState>(@lumio).total_locked
    }

    #[view]
    ///
    public fun get_total_unlocked(): u64 acquires StakingState {
        borrow_global<StakingState>(@lumio).total_unlocked
    }

    #[view]
    ///
    public fun get_user_stakes_count(user_addr: address): u64 acquires StakingState {
        let state = borrow_global<StakingState>(@lumio);
        get_user_stakes_count_inner(state, user_addr)
    }

    fun get_user_stakes_count_inner(
        state: &StakingState, user_addr: address
    ): u64 {
        if (state.users.contains(user_addr)) *state.users.borrow(user_addr)
        else 0
    }

    // #[view]
    // ///
    // public fun get_user_stake(user_addr: address, id: u64): () acquires StakingState {
    //     let state = borrow_global<StakingState>(@lumio);

    // }

    #[view]
    ///
    public fun create_stake_index_address(user_addr: address, id: u64): address {
        let payload = bcs::to_bytes(&user_addr);
        payload.append(bcs::to_bytes(&id));

        util::address_from_bytes(sha3_256(payload))
    }

    // Events.

    #[event]
    struct LumioStakingInitializedEvent has drop, store {
        lumio_metadata: Object<Metadata>,
        assets_holder_addr: address
    }

    #[event]
    struct StakeEvent<phantom Duration> has drop, store {
        user_addr: address,
        in_behalf_of: address,
        id: u64,
        amount: u64,
        unlock_date: u64
    }
}

