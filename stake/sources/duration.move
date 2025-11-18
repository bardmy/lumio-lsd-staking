module lumio::duration {
    use std::string::{String, utf8};
    use aptos_std::type_info;

    // Errors.

    /// When provided generic is not from lumio::duration module.
    const ERR_INVALID_DURATION_TYPE: u64 = 200;
    /// Unreachable condition.
    const ERR_UNREACHABLE: u64 = 201;

    // Constants.

    /// One month in seconds.
    const MONTH: u64 = 2629800;

    // Structures representing stake duration.

    struct OneMonth {}

    struct ThreeMonths {}

    struct SixMonths {}

    struct OneYear {}

    struct TwoYears {}

    public fun assert_lumio_duration<D>() {
        let type = type_info::type_of<D>();
        assert!(
            type.account_address() == @lumio && type.module_name() == b"duration",
            ERR_INVALID_DURATION_TYPE
        );
    }

    #[view]
    ///
    public fun seconds<D>(): u64 {
        if (is_same<OneMonth, D>()) MONTH
        // one month in seconds.
        else if (is_same<ThreeMonths, D>()) MONTH * 3
        // three months in seconds.
        else if (is_same<SixMonths, D>()) MONTH * 6
        // six months in seconds.
        else if (is_same<OneYear, D>()) MONTH * 12
        // one year in seconds.
        else if (is_same<TwoYears, D>()) MONTH * 24
        // two years in seconds.
        else abort ERR_UNREACHABLE
    }

    #[view]
    ///
    public fun selected<D>(): String {
        utf8(type_info::type_of<D>().struct_name())
    }

    /// Compares two generics.
    inline fun is_same<T1, T2>(): bool {
        type_info::type_of<T1>() == type_info::type_of<T2>()
    }
}

