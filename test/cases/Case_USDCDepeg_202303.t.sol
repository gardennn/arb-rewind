// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {CaseBase} from "./CaseBase.sol";
import {Tokens} from "../../src/tokens/Tokens.sol";
import {ArbCandidate} from "../../src/ArbDetector.sol";

// Historical context: Mar 11, 2023 - Silicon Valley Bank froze Circle's ~$3.3B
// USDC reserve. USDC briefly traded as low as $0.87 on CEXes; on-chain stable
// pools hit multi-percent skew before being arbed flat over the next ~48h.
//
// Block 16_804_000 sits inside the *active panic* window — a few hours into
// the SVB dislocation, before MEV searchers had fully compressed the
// cross-DEX stable triangle spread. An offline scan of blocks 16_800_000 –
// 16_816_000 (see repo history) found this block carries the strongest
// post-friction signal in that range: 4 profitable triangles, top ≈ +0.156%.
// Later blocks (e.g. 16_818_000, used pre-refactor) sit in the recovery tail
// and show `profitable = 0` — the same pipeline, same tokens, but MEV had
// already pulled the cycles below friction by then.
//
// This test locks in "there was a real opportunity here, and we find it".
contract CaseUSDCDepeg202303Test is CaseBase {
    function setUp() public {
        vm.createSelectFork("mainnet", 16_804_000);
        _deployInfra();
    }

    function test_scan_and_detect_triangles() public {
        address[] memory tokens = new address[](4);
        tokens[0] = Tokens.USDC;
        tokens[1] = Tokens.USDT;
        tokens[2] = Tokens.DAI;
        tokens[3] = Tokens.WETH;

        uint256[] memory probes = new uint256[](4);
        probes[0] = 10_000e6; // USDC
        probes[1] = 10_000e6; // USDT
        probes[2] = 10_000e18; // DAI
        probes[3] = 5e18; // WETH

        _populateGraph(tokens, probes);

        address[] memory intermediates = new address[](3);
        intermediates[0] = Tokens.USDT;
        intermediates[1] = Tokens.DAI;
        intermediates[2] = Tokens.WETH;

        ArbCandidate[] memory all = detector.findAllTriangles(Tokens.USDC, intermediates);
        ArbCandidate[] memory profitable = detector.findTriangles(Tokens.USDC, intermediates);

        emit log_named_uint("profitable triangles", profitable.length);
        _printTop(all, 5);

        // The pipeline must enumerate *and* surface at least one real
        // opportunity at this block. A regression that silently dropped to
        // zero would mean either the scanners stopped returning edges or
        // the log-space math flipped sign; both should fail loudly.
        assertGt(all.length, 0, "pipeline failed to enumerate any cycle");
        assertGt(profitable.length, 0, "expected MEV-available arb at this block");
    }
}
