#[test_only]
module lumio::stake_tests {
    use std::string::utf8;
    use aptos_framework::account;
    use aptos_framework::genesis;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    use lumio::duration;
    use lumio::common::new_account;
    use lumio::fa::{create_admin_with_assets, meta, LSD, mint, amount};

    use lumio::staking;
    use lumio::duration::{OneMonth, ThreeMonths, SixMonths, OneYear, TwoYears};

    // Initialization tests

    #[test]
    fun test_stake_init() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();

        // Check module uninitialized by default.
        assert!(!staking::is_initialized());

        // Initialize staking.
        staking::init(&lumio, meta<LSD>());

        // Check initial state.
        assert!(staking::is_initialized());
        assert!(
            staking::get_staking_asset_metadata() == meta<LSD>()
        );
        assert!(staking::get_total_locked() == 0);
        assert!(staking::get_total_unlocked() == 0);

        // Check assets holder.
        let holder_addr =
            account::create_resource_address(&@lumio, b"lumio-stake-assets-holder");
        assert!(staking::get_holder_address() == holder_addr);
        assert!(staking::get_holder_balance() == 0);
    }

    #[test]
    #[expected_failure(abort_code = staking::ERR_SIGNER_NOT_OWNER)]
    fun test_stake_init_with_wrong_owner_should_fail() {
        let alice = new_account(@alice);
        let _ = create_admin_with_assets();

        // Attempt to initialize staking with wrong owner.
        staking::init(&alice, meta<LSD>());
    }

    // Stake & Unstake tests

    #[test]
    fun test_staking_stake_e2e() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        // Mint some LSD for alice.
        let amount_to_stake = amount<LSD>(28_500, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        // Check balances before.
        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == amount_to_stake
        );
        assert!(staking::get_holder_balance() == 0);

        // Stake from alice.
        staking::stake<SixMonths>(&alice, amount_to_stake, @carol);

        // Check alice cannot unlock.
        assert!(!staking::can_unlock(@alice, 0));

        // Check module state.
        assert!(staking::get_holder_balance() == amount_to_stake);
        assert!(staking::get_total_locked() == amount_to_stake);
        assert!(staking::get_total_unlocked() == 0);
        assert!(staking::get_users_count() == 1);
        assert!(staking::get_stakes_count() == 1);

        // Check alice state.
        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == 0
        );
        assert!(staking::get_user_stakes_count(@alice) == 1);

        // Check alice stake1 params.
        let lock_time = timestamp::now_seconds();
        assert!(staking::get_user_stakes_count(@alice) == 1);
        let (
            s0_owner, s0_ibo, s0_id, s0_amount, s0_duration, s0_lock_date, s0_unlock_date
        ) = staking::get_user_stake(@alice, 0);
        assert!(s0_owner == @alice);
        assert!(s0_ibo == @carol);
        assert!(s0_id == 0);
        assert!(s0_amount == amount_to_stake);
        assert!(s0_duration == utf8(b"SixMonths"));
        assert!(s0_lock_date == lock_time);
        assert!(
            s0_unlock_date == lock_time + duration::seconds<SixMonths>()
        );

        // Wait six months.
        timestamp::fast_forward_seconds(duration::seconds<SixMonths>());

        // Unstake from alice.
        assert!(staking::can_unlock(@alice, 0));
        staking::unstake(&alice, 0);

        // Check module state.
        assert!(staking::get_holder_balance() == 0);
        assert!(staking::get_total_locked() == amount_to_stake);
        assert!(staking::get_total_unlocked() == amount_to_stake);
        assert!(staking::get_users_count() == 1);
        assert!(staking::get_stakes_count() == 1);

        // Check alice state.
        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == amount_to_stake
        );
        assert!(staking::get_user_stakes_count(@alice) == 1);

        // Check alice stake0 params after unstake.
        assert!(staking::get_user_stakes_count(@alice) == 1);
        let (
            s0_owner, s0_ibo, s0_id, s0_amount, s0_duration, s0_lock_date, s0_unlock_date
        ) = staking::get_user_stake(@alice, 0);
        assert!(s0_owner == @alice);
        assert!(s0_ibo == @carol);
        assert!(s0_id == 0);
        assert!(s0_amount == 0);
        assert!(s0_duration == utf8(b"SixMonths"));
        assert!(s0_lock_date == lock_time);
        assert!(
            s0_unlock_date == lock_time + duration::seconds<SixMonths>()
        );
    }

    // Unstake tests. Exact time

    #[test]
    fun test_unstake_one_month_succeeds_at_exact_time() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<OneMonth>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<OneMonth>();
        timestamp::fast_forward_seconds(duration_seconds);

        assert!(staking::can_unlock(@alice, 0));
        staking::unstake(&alice, 0);

        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == amount_to_stake
        );
    }

    #[test]
    fun test_unstake_three_months_succeeds_at_exact_time() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<ThreeMonths>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<ThreeMonths>();
        timestamp::fast_forward_seconds(duration_seconds);

        assert!(staking::can_unlock(@alice, 0));
        staking::unstake(&alice, 0);

        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == amount_to_stake
        );
    }

    #[test]
    fun test_unstake_six_months_succeeds_at_exact_time() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<SixMonths>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<SixMonths>();
        timestamp::fast_forward_seconds(duration_seconds);

        assert!(staking::can_unlock(@alice, 0));
        staking::unstake(&alice, 0);

        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == amount_to_stake
        );
    }

    #[test]
    fun test_unstake_one_year_succeeds_at_exact_time() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<OneYear>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<OneYear>();
        timestamp::fast_forward_seconds(duration_seconds);

        assert!(staking::can_unlock(@alice, 0));
        staking::unstake(&alice, 0);

        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == amount_to_stake
        );
    }

    #[test]
    fun test_unstake_two_years_succeeds_at_exact_time() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<TwoYears>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<TwoYears>();
        timestamp::fast_forward_seconds(duration_seconds);

        assert!(staking::can_unlock(@alice, 0));
        staking::unstake(&alice, 0);

        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == amount_to_stake
        );
    }

    // Unstake tests. A second before unlock date (should fail)

    #[test]
    #[expected_failure(abort_code = staking::ERR_TOO_EARLY_TO_UNLOCK)]
    fun test_unstake_one_month_fails_one_second_before() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<OneMonth>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<OneMonth>();
        timestamp::fast_forward_seconds(duration_seconds - 1);

        staking::unstake(&alice, 0);
    }

    #[test]
    #[expected_failure(abort_code = staking::ERR_TOO_EARLY_TO_UNLOCK)]
    fun test_unstake_three_months_fails_one_second_before() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<ThreeMonths>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<ThreeMonths>();
        timestamp::fast_forward_seconds(duration_seconds - 1);

        staking::unstake(&alice, 0);
    }

    #[test]
    #[expected_failure(abort_code = staking::ERR_TOO_EARLY_TO_UNLOCK)]
    fun test_unstake_six_months_fails_one_second_before() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<SixMonths>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<SixMonths>();
        timestamp::fast_forward_seconds(duration_seconds - 1);

        staking::unstake(&alice, 0);
    }

    #[test]
    #[expected_failure(abort_code = staking::ERR_TOO_EARLY_TO_UNLOCK)]
    fun test_unstake_one_year_fails_one_second_before() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<OneYear>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<OneYear>();
        timestamp::fast_forward_seconds(duration_seconds - 1);

        staking::unstake(&alice, 0);
    }

    #[test]
    #[expected_failure(abort_code = staking::ERR_TOO_EARLY_TO_UNLOCK)]
    fun test_unstake_two_years_fails_one_second_before() {
        let lumio = new_account(@lumio);
        let _ = create_admin_with_assets();
        let alice = new_account(@alice);

        genesis::setup();
        staking::init(&lumio, meta<LSD>());

        let amount_to_stake = amount<LSD>(1000, 0);
        let assets = mint<LSD>(amount_to_stake);
        primary_fungible_store::deposit(@alice, assets);

        staking::stake<TwoYears>(&alice, amount_to_stake, @alice);

        let duration_seconds = duration::seconds<TwoYears>();
        timestamp::fast_forward_seconds(duration_seconds - 1);

        staking::unstake(&alice, 0);
    }
}

