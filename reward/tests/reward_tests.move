#[test_only]
module lumio::reward_tests {
    use aptos_framework::primary_fungible_store;

    use lumio::fa::{create_admin_with_assets, meta, LSD, mint};
    use lumio::common::new_account;

    use lumio::reward;

    #[test]
    fun test_reward_e2e() {
        let lumio = new_account(@lumio);
        let alice = new_account(@alice);
        let bob = new_account(@bob);
        let carol = new_account(@carol);
        let _ = create_admin_with_assets();

        reward::init(&lumio, meta<LSD>());
        assert!(reward::distributor_balance() == 0);

        let assets = mint<LSD>(10000);
        primary_fungible_store::deposit(@lumio, assets);

        reward::deposit(&lumio, 10000);

        assert!(
            primary_fungible_store::balance(@lumio, meta<LSD>()) == 0
        );
        assert!(reward::distributor_balance() == 10000);

        reward::withdraw(&lumio, 5000);
        assert!(reward::distributor_balance() == 5000);
        assert!(
            primary_fungible_store::balance(@lumio, meta<LSD>()) == 5000
        );

        reward::append_claim_list(
            &lumio,
            vector[@alice, @bob, @carol, @alice],
            vector[100, 200, 300, 1000]
        );

        assert!(reward::user_claim_balance(@alice) == 1100);
        assert!(reward::user_claim_balance(@bob) == 200);
        assert!(reward::user_claim_balance(@carol) == 300);

        reward::claim(&alice);
        assert!(
            primary_fungible_store::balance(@alice, meta<LSD>()) == 1100
        );
        assert!(reward::user_claim_balance(@alice) == 0);
        assert!(reward::distributor_balance() == 5000 - 1100);

        reward::claim(&bob);
        assert!(
            primary_fungible_store::balance(@bob, meta<LSD>()) == 200
        );
        assert!(reward::user_claim_balance(@bob) == 0);
        assert!(
            reward::distributor_balance() == 5000 - 1100 - 200
        );

        reward::claim(&carol);
        assert!(
            primary_fungible_store::balance(@carol, meta<LSD>()) == 300
        );
        assert!(reward::user_claim_balance(@carol) == 0);
        assert!(
            reward::distributor_balance() == 5000 - 1100 - 200 - 300
        );
    }
}

