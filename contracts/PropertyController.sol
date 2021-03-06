pragma solidity 0.4.18;


import "./base/AddressChecker.sol";
import "./base/Owned.sol";
import './adapters/MultiEventsHistoryAdapter.sol';


contract PropertyFactoryInterface {
    function createProperty(address, address, string, string, uint8, uint256) public returns(address);
}


contract PropertyRegistryInterface {
    function register(address) returns(bool);
    function relevant(address) returns(bool);
    function remove(address, bool) returns(bool);
}


contract DeedRegistryInterface {
    function register(address) returns(bool);
    function remove(address) returns(bool);
}


contract PropertyProxyInterface {
    function setPropertyToPendingState(address, address) returns(bool);
    function migrateProperty(address, address) returns(bool);
}


contract PropertyInterface {
    function status() returns(uint);
    function getTitleOwner() returns(address);
}


contract DeedInterface {
    function reserve(address, uint256, address, address, address, address[], uint256[]) returns(bool);
    function approve() returns(bool);
    function changeIntermediary(uint, address) returns(bool);
    function metaDeed() returns(address);
    function property() returns(address);
    function seller() returns(address);
    function buyer() returns(address);
    function escrow() returns(address);
}


contract UsersRegistryInterface {
    function getRole(address) returns(uint);
}


contract PropertyController is Owned, MultiEventsHistoryAdapter {

    address public propertyProxy;
    address public propertyFactory;
    address public propertyRegistry;
    address public deedRegistry;
    address public usersRegistry;
    address public token;
    address public feeCalc;

    address public companyWallet;
    address public networkGrowthPoolWallet;


    /// EVENTS ///

    event DeedReserved(address self, address deed, address property, address seller, address buyer, address escrow);
    event DeedApproved(address self, address deed);


    /// CONSTRUCTOR ///

    function PropertyController(
        address _propertyProxy,
        address _propertyFactory,
        address _propertyRegistry,
        address _deedRegistry,
        address _usersRegistry,
        address _tokenAddress,
        address _feeCalc
    ) {
        propertyProxy = _propertyProxy;
        propertyFactory = _propertyFactory;
        propertyRegistry = _propertyRegistry;
        deedRegistry = _deedRegistry;
        usersRegistry = _usersRegistry;
        token = _tokenAddress;
        feeCalc = _feeCalc;
    }


    /// SETTINGS ///

    function setupEventsHistory(address _eventsHistory) public onlyContractOwner returns(bool) {
        if (getEventsHistory() != 0x0) {
            return false;
        }
        _setEventsHistory(_eventsHistory);
        return true;
    }

    function setPropertyProxy(address _propertyProxy)
        onlyContractOwner
        notNull(_propertyProxy)
    returns(bool) {
        _emitServiceChanged("PropertyProxy", propertyProxy, _propertyProxy);
        propertyProxy = _propertyProxy;
        return true;
    }

    function setPropertyFactory(address _propertyFactory)
        onlyContractOwner
        notNull(_propertyFactory)
    returns(bool) {
        _emitServiceChanged("PropertyFactory", propertyFactory, _propertyFactory);
        propertyFactory = _propertyFactory;
        return true;
    }

    function setPropertyRegistry(address _propertyRegistry)
        onlyContractOwner
        notNull(_propertyRegistry)
    returns(bool) {
        _emitServiceChanged("PropertyRegistry", propertyRegistry, _propertyRegistry);
        propertyRegistry = _propertyRegistry;
        return true;
    }

    function setDeedRegistry(address _deedRegistry)
        onlyContractOwner
        notNull(_deedRegistry)
    returns(bool) {
        _emitServiceChanged("DeedRegistry", deedRegistry, _deedRegistry);
        deedRegistry = _deedRegistry;
        return true;
    }

    function setUsersRegistry(address _usersRegistry)
        onlyContractOwner
        notNull(_usersRegistry)
    returns(bool) {
        _emitServiceChanged("UsersRegistry", usersRegistry, _usersRegistry);
        usersRegistry = _usersRegistry;
        return true;
    }

    function setToken(address _token)
        onlyContractOwner
        notNull(_token)
    returns(bool) {
        _emitServiceChanged("Token", token, _token);
        token = _token;
        return true;
    }

    function setFeeCalc(address _feeCalc)
        onlyContractOwner
        notNull(_feeCalc)
    returns(bool) {
        _emitServiceChanged("FeeCalc", feeCalc, _feeCalc);
        feeCalc = _feeCalc;
        return true;
    }

    function setFeeWallets(
        address _companyWallet,
        address _networkGrowthPoolWallet
    )
        onlyContractOwner
    returns(bool) {
        require(_companyWallet != address(0) && _networkGrowthPoolWallet != address(0));
        companyWallet = _companyWallet;
        networkGrowthPoolWallet = _networkGrowthPoolWallet;
        // TODO: Separate setters for wallets, emit wallet changed.
        return true;
    }


    event D(address d);

    /// PROPERTY OPERATIONS ///

    // CREATE / REGISTER //

    function createAndRegisterProperty(
        address _previousVersion, address _owner, string _name, string _physicalAddress, uint8 _areaType, uint256 _area
    )
        public
        onlyContractOwner
    returns(bool) {
        address property = _createProperty(_previousVersion, _owner, _name, _physicalAddress, _areaType, _area);
        if (_previousVersion != address(0)) {
            // TODO: Test it properly
            assert(_migrateProperty(_previousVersion, property));
        }
        return _registerProperty(property);
    }

    function _createProperty(
        address _previousVersion, address _owner, string _name, string _physicalAddress, uint8 _areaType, uint256 _area
    )
        internal
    returns(address) {
        // Create property contract
        // TODO: Check that the owner is registered.
        return PropertyFactoryInterface(propertyFactory).createProperty(
            _previousVersion, _owner, _name, _physicalAddress, _areaType, _area
        );
    }

    function registerProperty(address _property) public onlyContractOwner returns(bool) {
        return _registerProperty(_property);
    }

    function _registerProperty(address _property) internal notNull(_property) returns(bool) {
        // Add property contract to the property registry
        PropertyRegistryInterface PropertyRegistry = PropertyRegistryInterface(propertyRegistry);
        assert(PropertyRegistry.register(_property));
        return true;
    }


    // REMOVE / MIGRATE //

    function removeProperty(address _property) public onlyContractOwner returns(bool) {
        return _removeProperty(_property, false);
    }

    function _migrateProperty(address _previousVersion, address _to) internal returns(bool) {
        PropertyProxyInterface PropertyProxy = PropertyProxyInterface(propertyProxy);
        assert(PropertyProxy.migrateProperty(_previousVersion, _to));
        return _removeProperty(_previousVersion, true);
    }

    function _removeProperty(address _property, bool _migrated) internal returns(bool) {
        PropertyRegistryInterface PropertyRegistry = PropertyRegistryInterface(propertyRegistry);
        return PropertyRegistry.remove(_property, _migrated);
    }


    /// DEED OPERATIONS ///

    /**
     * Reserve pre-deployed deed for the following Property and parties.
     */
    function reserveDeed(
        address _deed,
        address _property,
        uint256 _price,
        address _seller,
        address _buyer,
        address _escrow,
        address[] _intermediaries,
        uint256[] _payments
    )
        public
        onlyContractOwner
        notNull(_deed)
        returns(bool)
    {

        // FIXME: Check roles
        DeedInterface Deed = DeedInterface(_deed);
        if (!_validateReservation(_property, Deed, _seller)) {
            _emitError("Reservation failed");
            return false;
        }

        bool success = Deed.reserve(_property, _price, _seller, _buyer, _escrow, _intermediaries, _payments);
        if (success) {
            _emitDeedReserved(_deed, _property, _seller, _buyer, _escrow);
            PropertyProxyInterface PropertyProxy = PropertyProxyInterface(propertyProxy);
            assert(PropertyProxy.setPropertyToPendingState(_property, _deed));
            assert(_registerDeed(_deed));
            return true;
        }
        return false;
    }

    function _validateReservation(address _property, DeedInterface _deed, address _seller) internal returns(bool) {
        if (_deed.metaDeed() == address(0)) {
            return false;
        }
        // Ensure the Property is relevant
        PropertyRegistryInterface PropertyRegistry = PropertyRegistryInterface(propertyRegistry);
        if (!PropertyRegistry.relevant(_property)) {
            return false;
        }
        // Ensure Property has initial status
        PropertyInterface Property = PropertyInterface(_property);
        if (Property.status() != 0) {
            return false;
        }
        address seller = Property.getTitleOwner();
        if (_seller != seller) {
            return false;
        }
        return true;
    }

    /**
     * Save Deed address at the Deed Registry.
     */
    function registerDeed(address _deed) public onlyContractOwner returns(bool) {
        return _registerDeed(_deed);
    }

    function _registerDeed(address _deed) internal notNull(_deed) returns(bool) {
        DeedRegistryInterface DeedRegistry = DeedRegistryInterface(deedRegistry);
        return DeedRegistry.register(_deed);
    }

    /**
     * Remove Deed address from the Deed Registry.
     */
    function removeDeed(address _deed) public onlyContractOwner returns(bool) {
        DeedRegistryInterface DeedRegistry = DeedRegistryInterface(deedRegistry);
        return DeedRegistry.remove(_deed);
    }

    function changeDeedIntermediary(address _deed, uint _intermediariesIndex, address _newActor)
        public
        onlyContractOwner
        notNull(_deed)
        notNull(_newActor)
    returns(bool) {
        DeedInterface Deed = DeedInterface(_deed);
        return Deed.changeIntermediary(_intermediariesIndex, _newActor);
    }




    /// MULTI EVENTS HISTORY ///


    function _emitDeedReserved(address _deed, address _property, address _seller, address _buyer, address _escrow) internal {
        PropertyController(getEventsHistory()).emitDeedReserved(_deed, _property, _seller, _buyer, _escrow);
    }

    function _emitDeedApproved(address _deed) internal {
        PropertyController(getEventsHistory()).emitDeedApproved(_deed);
    }


    function emitDeedReserved(address _deed, address _property, address _seller, address _buyer, address _escrow) {
        DeedReserved(_self(), _deed, _property, _seller, _buyer, _escrow);
    }

    function emitDeedApproved(address _deed) {
        DeedApproved(_self(), _deed);
    }

    /// RESTRICTIONS & DISASTER RECOVERY ///

    function kill() public onlyContractOwner {
        selfdestruct(msg.sender);
    }

    // TODO: Add maintenance mode

}
