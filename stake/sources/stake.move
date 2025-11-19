module lumio::staking {
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

    use lumio::duration::{Self, selected};

    // Errors.

    /// When signer is not an owner.
    const ERR_SIGNER_NOT_OWNER: u64 = 100;
    /// When staking module is not initialized.
    const ERR_NOT_INITIALIZED: u64 = 101;
    /// When user provided zero amount.
    const ERR_ZERO_AMOUNT: u64 = 102;
    /// When stake with same index address already exists. Should be unreachable.
    const ERR_STAKE_INDEX_ADDR_ALRD_EXISTS: u64 = 103;
    /// When user has no stakes at all.
    const ERR_USER_HAS_NO_STAKES: u64 = 104;
    /// When user has no stake with specified id.
    const ERR_STAKE_DOESNT_EXIST: u64 = 105;
    /// When user tries to unlock early.
    const ERR_TOO_EARLY_TO_UNLOCK: u64 = 106;
    /// When user tries to unlock same stake again.
    const ERR_STAKE_ALREADY_UNLOCKED: u64 = 107;

    // Resources.

    /// Stores user stake details.
    struct Stake has store {
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
        // Check module initialized.
        assert!(is_initialized(), ERR_NOT_INITIALIZED);
        // Check amount > 0.
        assert!(amount > 0, ERR_ZERO_AMOUNT);
        // Check `Duration` is correct generic and get it struct name.
        let duration = selected<Duration>();

        let state = borrow_global_mut<StakingState>(@lumio);

        // Transfer assets to holder.
        let holder_addr = account::get_signer_capability_address(&state.assets_holder);
        let lumio_metadata = state.lumio_metadata;
        primary_fungible_store::transfer(user_acc, lumio_metadata, holder_addr, amount);

        // Get current stake id and increase user stake counter.
        let user_addr = signer::address_of(user_acc);
        let current_stake_id =
            if (!state.users.contains(user_addr)) {
                state.users.upsert(user_addr, 1);
                0
            } else {
                let counter = state.users.borrow_mut(user_addr);
                let current_id = *counter;

                *counter = *counter + 1;

                current_id
            };

        // Create stake data.
        let now = timestamp::now_seconds();
        let unlock_date = now + duration::seconds<Duration>();
        let user_stake = Stake {
            owner: user_addr,
            in_behalf_of,
            id: current_stake_id,
            amount,
            duration,
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
        state.stakes.add(stake_index_addr, user_stake);
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

    public entry fun unstake(user_acc: &signer, id: u64) acquires StakingState {
        // Check module initialized.
        assert!(is_initialized(), ERR_NOT_INITIALIZED);

        // Check user has some stakes.
        let state = borrow_global_mut<StakingState>(@lumio);
        let user_addr = signer::address_of(user_acc);
        assert!(state.users.contains(user_addr), ERR_USER_HAS_NO_STAKES);

        // Check stake with `id` exits for user.
        let stake_index_addr = create_stake_index_address(user_addr, id);
        assert!(state.stakes.contains(stake_index_addr), ERR_STAKE_DOESNT_EXIST);

        // Check unlock date.
        let user_stake = state.stakes.borrow_mut(stake_index_addr);
        let now = timestamp::now_seconds();
        assert!(user_stake.unlock_date <= now, ERR_TOO_EARLY_TO_UNLOCK);

        // Check user stake wasn't unlocked before.
        let locked_amount = user_stake.amount;
        assert!(locked_amount > 0, ERR_STAKE_ALREADY_UNLOCKED);

        // Set stake amount to 0 and increase total unlocked value.
        user_stake.amount = 0;
        state.total_unlocked = state.total_unlocked + locked_amount;

        // Transfer assets back to user.
        let holder_acc = &account::create_signer_with_capability(&state.assets_holder);
        let lumio_metadata = state.lumio_metadata;
        primary_fungible_store::transfer(
            holder_acc,
            lumio_metadata,
            user_addr,
            locked_amount
        );

        // Emit unstake event.
        event::emit(
            UnstakeEvent {
                user_addr,
                in_behalf_of: user_stake.in_behalf_of,
                id,
                amount: locked_amount
            }
        );
    }

    // View functions.

    #[view]
    /// Returns `true` if module is initialized.
    public fun is_initialized(): bool {
        exists<StakingState>(@lumio)
    }

    #[view]
    /// Returns `total_locked` amount.
    public fun get_total_locked(): u64 acquires StakingState {
        borrow_global<StakingState>(@lumio).total_locked
    }

    #[view]
    /// Returns `total_unlocked` amount.
    public fun get_total_unlocked(): u64 acquires StakingState {
        borrow_global<StakingState>(@lumio).total_unlocked
    }

    #[view]
    /// Returns amount of users with stakes.
    public fun get_users_count(): u64 acquires StakingState {
        borrow_global<StakingState>(@lumio).users.length()
    }

    #[view]
    /// Returns total amount of stakes.
    public fun get_stakes_count(): u64 acquires StakingState {
        borrow_global<StakingState>(@lumio).stakes.length()
    }

    #[view]
    /// Returns staking asset Metadata.
    public fun get_staking_asset_metadata(): Object<Metadata> acquires StakingState {
        borrow_global<StakingState>(@lumio).lumio_metadata
    }

    #[view]
    /// Returns module assets holder account address.
    public fun get_holder_address(): address acquires StakingState {
        account::get_signer_capability_address(
            &borrow_global<StakingState>(@lumio).assets_holder
        )
    }

    #[view]
    /// Returns module assets holder account balance.
    public fun get_holder_balance(): u64 acquires StakingState {
        let state = borrow_global<StakingState>(@lumio);
        let holder_addr = account::get_signer_capability_address(&state.assets_holder);
        let metadata = state.lumio_metadata;

        primary_fungible_store::balance(holder_addr, metadata)
    }

    #[view]
    /// Retruns user stakes amount.
    public fun get_user_stakes_count(user_addr: address): u64 acquires StakingState {
        let state = borrow_global<StakingState>(@lumio);

        if (state.users.contains(user_addr)) *state.users.borrow(user_addr)
        else 0
    }

    #[view]
    /// Returns user stake params.
    public fun get_user_stake(
        user_addr: address, id: u64
    ): (address, address, u64, u64, String, u64, u64) acquires StakingState {
        let state = borrow_global<StakingState>(@lumio);

        let stake_index_addr = create_stake_index_address(user_addr, id);
        let s = state.stakes.borrow(stake_index_addr);

        (s.owner, s.in_behalf_of, s.id, s.amount, s.duration, s.lock_date, s.unlock_date)
    }

    #[view]
    /// Returns `true` if assets could be unlocked.
    public fun can_unlock(user_addr: address, id: u64): bool acquires StakingState {
        let stake_index_addr = create_stake_index_address(user_addr, id);
        let now = timestamp::now_seconds();
        let user_stake =
            borrow_global<StakingState>(@lumio).stakes.borrow(stake_index_addr);

        now >= user_stake.unlock_date
    }

    #[view]
    /// Generates stake index address from user address and stake id.
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

    #[event]
    struct UnstakeEvent has drop, store {
        user_addr: address,
        in_behalf_of: address,
        id: u64,
        amount: u64
    }
}

