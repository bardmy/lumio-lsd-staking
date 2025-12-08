module lumio::reward {
    use std::signer;

    use aptos_std::table_with_length::{Self, TableWithLength};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::object::Object;
    use aptos_framework::fungible_asset::Metadata;

    // Errors.

    /// When signer is not an owner.
    const ERR_SIGNER_NOT_OWNER: u64 = 200;
    /// When lengths of users and amounts vectors are not equal.
    const ERR_INVALID_LENGTHS: u64 = 201;
    /// When user has nothing to claim.
    const ERR_USER_HAS_NOTHING_TO_CLAIM: u64 = 202;
    /// When user has already claimed.
    const ERR_ALREADY_CLAIMED: u64 = 203;

    struct DistributorState has key {
        // Current balance of the distributor.
        balance: u64,
        // Lumio FungibleAsset metadata.
        lumio_metadata: Object<Metadata>,
        // Account to hold assets to distribute.
        assets_holder: SignerCapability,
        // Table to store claim requests.
        claim_requests: TableWithLength<address, u64>
    }

    /// Initialization
    public entry fun init(
        lumio_acc: &signer, lumio_metadata: Object<Metadata>
    ) {
        let lumio_acc_addr = signer::address_of(lumio_acc);
        assert!(lumio_acc_addr == @lumio, ERR_SIGNER_NOT_OWNER);

        let (_, asset_holder_sig_cap) =
            account::create_resource_account(lumio_acc, b"reward-assets-holder");

        let state = DistributorState {
            balance: 0,
            lumio_metadata,
            assets_holder: asset_holder_sig_cap,
            claim_requests: table_with_length::new()
        };
        move_to(lumio_acc, state);
    }

    public entry fun deposit(lumio_acc: &signer, amount: u64) {
        let lumio_acc_addr = signer::address_of(lumio_acc);
        assert!(lumio_acc_addr == @lumio, ERR_SIGNER_NOT_OWNER);

        let state = borrow_global_mut<DistributorState>(@lumio);
        let assets_holder_addr =
            account::get_signer_capability_address(&state.assets_holder);

        primary_fungible_store::transfer(
            lumio_acc,
            state.lumio_metadata,
            assets_holder_addr,
            amount
        );
        state.balance += amount;
    }

    public entry fun withdraw(lumio_acc: &signer, amount: u64) {
        let lumio_acc_addr = signer::address_of(lumio_acc);
        assert!(lumio_acc_addr == @lumio, ERR_SIGNER_NOT_OWNER);

        let state = borrow_global_mut<DistributorState>(@lumio);
        let assets_holder_signer =
            account::create_signer_with_capability(&state.assets_holder);

        primary_fungible_store::transfer(
            &assets_holder_signer,
            state.lumio_metadata,
            lumio_acc_addr,
            amount
        );
        state.balance -= amount;
    }

    public entry fun append_claim_list(
        lumio_acc: &signer, users: vector<address>, amounts: vector<u64>
    ) {
        let lumio_acc_addr = signer::address_of(lumio_acc);
        assert!(lumio_acc_addr == @lumio, ERR_SIGNER_NOT_OWNER);

        // Check lengths of users and amounts vectors.
        assert!(users.length() == amounts.length(), ERR_INVALID_LENGTHS);

        let state = borrow_global_mut<DistributorState>(@lumio);
        let claim_requests = &mut state.claim_requests;

        let i = 0;
        let len = users.length();
        while (i < len) {
            let user_addr = users[i];
            let amount = amounts[i];

            if (claim_requests.contains(user_addr)) {
                let current_amount = claim_requests.borrow_mut(user_addr);
                *current_amount += amount;
            } else {
                claim_requests.add(user_addr, amount);
            };

            i += 1;
        };
    }

    public entry fun claim(user_acc: &signer) {
        let state = borrow_global_mut<DistributorState>(@lumio);
        let claim_requests = &mut state.claim_requests;

        let user_addr = signer::address_of(user_acc);
        assert!(claim_requests.contains(user_addr), ERR_USER_HAS_NOTHING_TO_CLAIM);
        assert!(*claim_requests.borrow(user_addr) > 0, ERR_ALREADY_CLAIMED);

        let asset_holder_sig =
            account::create_signer_with_capability(&state.assets_holder);
        let amount = claim_requests.borrow_mut(user_addr);
        primary_fungible_store::transfer(
            &asset_holder_sig,
            state.lumio_metadata,
            user_addr,
            *amount
        );

        state.balance -=*amount;
        *amount = 0;
    }

    // View functions.

    #[view]
    public fun distributor_balance(): u64 {
        borrow_global<DistributorState>(@lumio).balance
    }

    #[view]
    public fun user_claim_balance(user_addr: address): u64 {
        assert!(
            borrow_global<DistributorState>(@lumio).claim_requests.contains(user_addr),
            ERR_USER_HAS_NOTHING_TO_CLAIM
        );
        *borrow_global<DistributorState>(@lumio).claim_requests.borrow(user_addr)
    }
}

