// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

struct Edge {
    address dexAdapter;
    address tokenIn;
    address tokenOut;
    uint256 rate1e18;
    uint24 feeTier;
    bytes32 poolId;
}

contract PriceGraph {
    mapping(bytes32 => Edge[]) private _edges;

    function addEdge(Edge memory edge) external {
        _edges[_key(edge.tokenIn, edge.tokenOut)].push(edge);
    }

    function getEdges(address tokenIn, address tokenOut) external view returns (Edge[] memory) {
        return _edges[_key(tokenIn, tokenOut)];
    }

    function hasEdge(address tokenIn, address tokenOut) external view returns (bool) {
        return _edges[_key(tokenIn, tokenOut)].length > 0;
    }

    function _key(address a, address b) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(a, b));
    }
}
