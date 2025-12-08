#[test_only]
module lumio::common {
    use aptos_framework::account;

    // Accounts.

    public fun new_account(account_addr: address): signer {
        if (!account::exists_at(account_addr)) {
            account::create_account_for_test(account_addr)
        } else {
            let cap = account::create_test_signer_cap(account_addr);
            account::create_signer_with_capability(&cap)
        }
    }
}

