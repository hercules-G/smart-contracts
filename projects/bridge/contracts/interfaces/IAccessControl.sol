// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity 0.8.11;

interface IAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool);

    function DEFAULT_ADMIN_ROLE() external view returns (bytes32);
}
