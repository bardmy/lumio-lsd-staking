#[test_only]
module lumio::fa {
    use std::option;
    use std::option::Option;
    use std::string;

    use aptos_std::math64;
    use aptos_std::type_info;
    use aptos_framework::account::create_signer_for_test;
    use aptos_framework::fungible_asset::{Self, BurnRef, FungibleAsset, Metadata, MintRef};
    use aptos_framework::object::{Self, Object};
    use aptos_framework::primary_fungible_store;

    /// Stores refs under @fa_admin for mint and burn.
    struct RefsFA has key {
        mint_ref: MintRef,
        burn_ref: BurnRef
    }

    // Admin account funcs.

    /// Create admin account.
    public fun create_fa_admin(): signer {
        create_signer_for_test(@fa_admin)
    }

    /// Create admin account with all predefined assets in one func.
    public fun create_admin_with_assets(): signer {
        let fa_admin_acc = create_fa_admin();
        create_predefined_asset<USDT>(&fa_admin_acc);
        create_predefined_asset<LSD>(&fa_admin_acc);

        fa_admin_acc
    }

    // Custom FungibleAsset handlers.

    /// Creates FungibleAsset with specified params.
    /// Returns MintRef and BurnRef of created asset.
    public fun create_custom_asset(
        fa_admin_acc: &signer,
        seed: vector<u8>,
        max_supply: Option<u128>,
        name: vector<u8>,
        symbol: vector<u8>,
        decimals: u8,
        icon_uri: vector<u8>,
        project_uri: vector<u8>
    ): (MintRef, BurnRef) {
        let constructor_ref = object::create_named_object(fa_admin_acc, seed);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            &constructor_ref,
            max_supply,
            string::utf8(name),
            string::utf8(symbol),
            decimals,
            string::utf8(icon_uri),
            string::utf8(project_uri)
        );

        let mint_ref = fungible_asset::generate_mint_ref(&constructor_ref);
        let burn_ref = fungible_asset::generate_burn_ref(&constructor_ref);

        (mint_ref, burn_ref)
    }

    /// Stores MintRef and BurnRef under `fa_admin_acc`.
    public fun save_fa_refs(
        fa_admin_acc: &signer,
        seed: vector<u8>,
        mint_ref: MintRef,
        burn_ref: BurnRef
    ) {
        let refs_constructor_ref = object::create_named_object(fa_admin_acc, seed);
        let refs_signer = object::generate_signer(&refs_constructor_ref);
        move_to(&refs_signer, RefsFA { mint_ref, burn_ref });
    }

    // Predefined FungibleAsset's.

    struct USDT {}

    struct LSD {}

    /// Retruns predefined `sybmol` and `decimals` of provided `FA`.
    fun predefined_symbol_and_decimals<FA>(): (vector<u8>, u8) {
        if (is_same_asset<USDT, FA>()) (b"USDT", 6)
        else if (is_same_asset<LSD, FA>()) (b"LSD", 8)
        else abort 11
    }

    /// Constructs predefined asset parameters for provided `FA`.
    /// Retruns `seed`, `name`, `symbol` and `decimals`
    fun predefined_asset_params<FA>(): (vector<u8>, vector<u8>, vector<u8>, u8) {
        let (symbol, decimals) = predefined_symbol_and_decimals<FA>();

        let name = copy symbol;
        name.append(b" Fungible Asset");

        let seed = copy symbol;
        seed.append(b"_FA_OBJ");

        (seed, name, symbol, decimals)
    }

    /// Creates FungibleAsset using using predefined `FA` params.
    /// Saves MintRef and BurnRef of created asset under `fa_admin_acc`.
    public fun create_predefined_asset<FA>(fa_admin_acc: &signer) {
        let (seed, name, symbol, decimals) = predefined_asset_params<FA>();

        let (mint_ref, burn_ref) =
            create_custom_asset(
                fa_admin_acc,
                seed,
                option::none(), // max_supply
                name,
                symbol,
                decimals,
                b"https://assets.panora.exchange/tokens/aptos/LSD.png",
                b"https://liquidswap.com/"
            );

        let refs_obj_seed = refs_seed(symbol);
        save_fa_refs(
            fa_admin_acc,
            refs_obj_seed,
            mint_ref,
            burn_ref
        );
    }

    // Mint & burn.

    /// Retunrs minted `amount` of provided FungibleAsset `FA`.
    ///
    /// Note: supports only predefined `FA` generics.
    ///          Use `mint_symb` for custom FA's.
    public fun mint<FA>(amount: u64): FungibleAsset acquires RefsFA {
        mint_symb(symb<FA>(), amount)
    }

    /// Retunrs minted `amount` of FungibleAsset with provided `symbol`.
    ///
    /// Note: works only if asset was created with `create_custom_asset`.
    ///          Use `mint` func for predefined FungibleAsset.
    public fun mint_symb(symbol: vector<u8>, amount: u64): FungibleAsset acquires RefsFA {
        let fa_refs = borrow_global_mut<RefsFA>(refs_addr(symbol));
        fungible_asset::mint(&fa_refs.mint_ref, amount)
    }

    /// Burns provided FungibleAsset.
    public fun burn(asset: FungibleAsset) acquires RefsFA {
        let metadata = fungible_asset::asset_metadata(&asset);
        let symbol = *fungible_asset::symbol(metadata).bytes();

        let fa_refs = borrow_global_mut<RefsFA>(refs_addr(symbol));
        fungible_asset::burn(&fa_refs.burn_ref, asset)
    }

    // Helpers to reduce code size in tests.

    /// Returns the composed amount for provided `FA`.
    /// Result is sum of the integer `b` and fractional `f` components.
    ///
    /// Note: supports only predefined `FA` generics.
    ///          Use `amount_from_symb` for custom FA's.
    public fun amount<FA>(b: u64, f: u64): u64 acquires RefsFA {
        amount_from_symb(symb<FA>(), b, f)
    }

    /// Returns the composed amount for FungibleAsset with provided `symbol`.
    /// Result is sum of the integer `b` and fractional `f` components.
    ///
    /// Note: works only if asset was created with `create_custom_asset`.
    ///          Use `amount` func for predefined FungibleAsset.
    public fun amount_from_symb(symbol: vector<u8>, b: u64, f: u64): u64 acquires RefsFA {
        let decimals_multiplier = asset_scale_from_symbol(symbol);

        // Common sense assert.
        assert!(f < decimals_multiplier * 10);

        (b * decimals_multiplier) + f
    }

    /// Returns metadata of provided `FA`.
    ///
    /// Note: supports only predefined `FA` generics.
    ///          Use `meta_from_symb` for custom FA's.
    public fun meta<FA>(): Object<Metadata> {
        meta_from_symb(symb<FA>())
    }

    /// Returns metadata of FungibleAsset using asset with provided `symbol`.
    ///
    /// Note: works only if asset was created with `create_custom_asset`.
    ///          Use `meta` func for predefined FungibleAsset.
    public fun meta_from_symb(symbol: vector<u8>): Object<Metadata> {
        object::address_to_object<Metadata>(asset_obj_addr(symbol))
    }

    /// Returns struct name of `FA` generic.
    public fun symb<FA>(): vector<u8> {
        type_info::type_of<FA>().struct_name()
    }

    /// Retruns FungibleAsset decimals multiplier for provided asset `sybmol`.
    ///
    /// Note: works only if asset was created with `create_custom_asset`.
    public fun asset_scale_from_symbol(symbol: vector<u8>): u64 acquires RefsFA {
        let refs = borrow_global<RefsFA>(refs_addr(symbol));
        let metadata = fungible_asset::mint_ref_metadata(&refs.mint_ref);

        math64::pow(10, (fungible_asset::decimals(metadata) as u64))
    }

    // Private funcs.

    /// Compares two generics.
    fun is_same_asset<T1, T2>(): bool {
        type_info::type_of<T1>() == type_info::type_of<T2>()
    }

    /// Creates refs object address from `symbol`.
    fun refs_addr(symbol: vector<u8>): address {
        // Append `symbol` to contain "_REFS" to create refs object addr.
        symbol.append(b"_REFS");

        object::create_object_address(&@fa_admin, symbol)
    }

    /// Creates refs object seed from `symbol`.
    fun refs_seed(symbol: vector<u8>): vector<u8> {
        // Append `symbol` to contain "_REFS" to create refs object seed.
        symbol.append(b"_REFS");
        symbol
    }

    /// Creates FungibleAsset object address from `symbol`.
    fun asset_obj_addr(symbol: vector<u8>): address {
        // Append `symbol` to contain "_FA_OBJ" to create metadata object addr.
        symbol.append(b"_FA_OBJ");

        object::create_object_address(&@fa_admin, symbol)
    }
}

