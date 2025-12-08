#[test_only]
module lumio::duration_tests {
    use std::string::utf8;

    use aptos_framework::aptos_coin;

    use lumio::duration;
    use lumio::duration::{
        seconds,
        selected,
        OneMonth,
        ThreeMonths,
        SixMonths,
        OneYear,
        TwoYears,
        ThreeYears
    };

    // Seconds tests

    #[test]
    fun test_duration_seconds() {
        assert!(seconds<OneMonth>() == 2629800);
        assert!(seconds<ThreeMonths>() == 2629800 * 3);
        assert!(seconds<SixMonths>() == 2629800 * 6);
        assert!(seconds<OneYear>() == 2629800 * 12);
        assert!(seconds<TwoYears>() == 2629800 * 24);
    }

    #[test]
    #[expected_failure(abort_code = duration::ERR_INVALID_DURATION_TYPE)]
    fun test_duration_seconds_with_wrong_module_generic_should_fail() {
        seconds<aptos_coin::AptosCoin>();
    }

    #[test]
    #[expected_failure(abort_code = duration::ERR_INVALID_DURATION_TYPE)]
    fun test_duration_seconds_with_correct_module_but_wrong_generic_should_fail() {
        seconds<ThreeYears>();
    }

    // Selected tests

    #[test]
    fun test_duration_selected() {
        assert!(selected<OneMonth>() == utf8(b"OneMonth"));
        assert!(
            selected<ThreeMonths>() == utf8(b"ThreeMonths")
        );
        assert!(selected<SixMonths>() == utf8(b"SixMonths"));
        assert!(selected<OneYear>() == utf8(b"OneYear"));
        assert!(selected<TwoYears>() == utf8(b"TwoYears"));
    }

    #[test]
    #[expected_failure(abort_code = duration::ERR_INVALID_DURATION_TYPE)]
    fun test_duration_selected_with_wrong_module_generic_should_fail() {
        selected<aptos_coin::AptosCoin>();
    }

    #[test]
    #[expected_failure(abort_code = duration::ERR_INVALID_DURATION_TYPE)]
    fun test_duration_selected_with_correct_module_but_wrong_generic_should_fail() {
        selected<ThreeYears>();
    }
}

