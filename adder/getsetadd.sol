pragma solidity ^0.6.3;
contract Adder {
    uint current;

    function get() public view returns (uint) {
        return current;
    }

    function set(uint x) public {
        current = x;
    }
    function add(uint x) public {
        current = current + x;
    }
}
