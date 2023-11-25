// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IProofOfIdentity.sol";

/**
 * @title MediChainPOI
 * @dev Example implementation of using the Proof of Identity contract to
 * permission access to a feature. Here, only users (Admins, Doctors and Patients)
 * who have established a sufficiently high competency rating will be allowed to
 * Admin: adds and removes doctors,
 * Doctor: adds medical reports and withdraws funds,
 * Patient: requests medical reports and pay to doctor,
 * set a value on the contract.
 * Read permission is available to all.
 */
contract MediChainPOI is AccessControl, Ownable {
    /* TYPE DECLARATIONS
    ==================================================*/
    // Struct to store patient information
    struct Patient {
        uint256 dateOfBirth;
        address patientAddress;
        uint256 lastVisitDate;
    }

    // Struct to store doctor information
    struct Doctor {
        address doctorAddress;
        string specialty;
        uint256 perSession;
        string timeAvailability;
        string rating;
    }

    // Struct to store medical report information
    struct MedicalReport {
        uint256 reportId;
        uint256 issueDate;
        string patientCondition;
        string summary;
        address doctorAddress;
        address patientAddress;
        uint256 amount;
        bool paid;
        bool submittedReport;
    }

    // Struct to store admin information
    struct Admin {
        address adminAddress;
    }

    /* STATE VARIABLES
    ==================================================*/
    // Counter for medical report IDs
    uint256 public reportCount;

    // Arrays to store all doctors and admins
    address[] public allDoctors;
    address[] public allAdmins;

    /**
     * @dev The competency rating threshold that must be met in order for an
     * account to pass the competency rating check.
     */
    uint256 private _competencyRatingThreshold;

    /**
     * @dev The Proof of Identity Contract.
     */
    IProofOfIdentity private _proofOfIdentity;

    bytes32 public constant DOCTOR_ROLE = keccak256("DOCTOR_ROLE");

    /* EVENTS
    ==================================================*/
    /**
     * @notice Emits the address of the doctor and the his/her specialty.
     * @param doctorAddress The address of doctor.
     * @param specialty The doctor's specialty.
     */
    event DoctorAdded(address indexed doctorAddress, string specialty);

    /**
     * @notice Emits the address of the docotr that removed.
     * @param doctorAddress The address of doctor.
     */
    event DoctorRemoved(address indexed doctorAddress);

    /**
     * @notice Emits the address of the admin that added.
     * @param adminAddress The address of admin.
     */
    event AdminAdded(address indexed adminAddress);

    /**
     * @notice Emits the address of the admin that removed.
     * @param adminAddress The address of admin.
     */
    event AdminRemoved(address indexed adminAddress);

    /**
     * @notice Emits the Medical Report Requested that made by patient.
     * @param reportId The report ID.
     * @param patientAddress The address of patient.
     * @param amount The doctor per session price.
     */
    event MedicalReportRequested(
        uint256 indexed reportId,
        address indexed patientAddress,
        uint256 amount
    );

    /**
     * @notice Emits the Medical Report Submitted that made by doctor.
     * @param reportId The report ID.
     * @param doctorAddress The address of doctor.
     */
    event MedicalReportSubmitted(
        uint256 indexed reportId,
        address indexed doctorAddress
    );

    /**
     * @notice Emits the new competency rating threshold value.
     * @param threshold The new competency rating threshold value.
     */
    event CompetencyRatingThresholdUpdated(uint256 threshold);

    /**
     * @notice Emits the new Proof of Identity contract address.
     * @param poiAddress The new Proof of Identity contract address.
     */
    event POIAddressUpdated(address indexed poiAddress);

    /* ERRORS
    ==================================================*/
    /**
     * @notice Error to throw when doctor's account exists.
     */
    error MediChainPOI__DoctorAlreadyExists();

    /**
     * @notice Error to throw when doctor's account does not exist.
     */
    error MediChainPOI__DoctorNotFounded();

    /**
     * @notice Error to throw when admin's account exists.
     */
    error MediChainPOI__AdminAlreadyExists();

    /**
     * @notice Error to throw when admin's account does not exist.
     */
    error MediChainPOI__AdminNotFounded();

    /**
     * @notice Error to throw when report does not exist.
     */
    error MediChainPOI__ReportNotFounded();

    /**
     * @notice Error to throw when patient's account does not exists.
     */
    error MediChainPOI__PatientNotFounded();

    /**
     * @notice Error to throw when the amount is zero or lower.
     */
    error MediChainPOI__AmountMustNotBeZero();

    /**
     * @notice Error to throw when the amount does not match.
     */
    error MediChainPOI__AmountMustMatch();

    /**
     * @notice Error to throw when Invalid Withdrawal Conditions.
     */
    error MediChainPOI__InvalidWithdrawalConditions();

    /**
     * @notice Error to throw when the sender is not the doctor.
     */
    error MediChainPOI__OnlyDoctorCanWithdraw();

    /**
     * @notice Error to throw when the zero address has been supplied and it
     * is not allowed.
     */
    error MediChainPOI__ZeroAddress();

    /**
     * @notice Error to throw when an account does not have a Proof of Identity
     * NFT.
     */
    error MediChainPOI__NoIdentityNFT();

    /**
     * @notice Error to throw when an account is suspended.
     */
    error MediChainPOI__Suspended();

    /**
     * @notice Error to throw when an invalid competency rating has been supplied.
     * @param rating The account's current competency rating.
     * @param threshold The minimum required competency rating.
     */
    error MediChainPOI__CompetencyRating(uint256 rating, uint256 threshold);

    /**
     * @notice Error to throw when an attribute has expired.
     * @param attribute The name of the required attribute
     */
    error MediChainPOI__AttributeExpired(string attribute, uint256 expiry);

    /* MAPPINGS
    ==================================================*/
    // Mapping to store patient data
    mapping(address => Patient) public patients;

    // Mapping to store doctor data
    mapping(address => Doctor) public doctors;

    // Mapping to store medical report data
    mapping(uint256 => MedicalReport) public medicalReports;

    // Mapping to store admin data
    mapping(address => Admin) public admins;

    /* MODIFIERS
    ==================================================*/
    /**
     * @dev Modifier to be used on any functions that require a user be
     * permissioned per this contract's definition.
     * Ensures that the account:
     * -    has a Proof of Identity NFT;
     * -    is not suspended; and
     * -    has established a sufficiently high competency rating and it is not
     *      expired.
     *
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     */
    modifier onlyPermissioned(address account) {
        // ensure the account has a Proof of Identity NFT
        if (!_hasID(account)) revert MediChainPOI__NoIdentityNFT();

        // ensure the account is not suspended
        if (_isSuspended(account)) revert MediChainPOI__Suspended();

        // ensure the account has a valid competency rating
        _checkCompetencyRatingExn(account);

        _;
    }

    /* FUNCTIONS
    ==================================================*/
    /* Constructor
    ========================================*/
    /**
     * @param proofOfIdentity_ The address of the Proof of Identity contract.
     * @param competencyRatingThreshold_ The competency rating threshold that
     * be met.
     */
    constructor(
        address proofOfIdentity_,
        uint256 competencyRatingThreshold_
    ) Ownable(msg.sender) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        setPOIAddress(proofOfIdentity_);
        setCompetencyRatingThreshold(competencyRatingThreshold_);
    }

    /* External
    ========================================*/
    /**
     * @notice Allows permissioned owners to add a new doctor.
     *
     * @dev Function to add a new doctor.
     * @param _doctorAddress Address of doctor.
     * @param _specialty Doctory specialty.
     * @param _perSession Fee per session charged by the doctor.
     * @param _timeAvailability Availability schedule of the doctor.
     * @param _rating Rating of the doctor.
     *
     * @dev
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     * May emit an `DoctorAdded` event.
     */

    function addDoctor(
        address _doctorAddress,
        string memory _specialty,
        uint256 _perSession,
        string memory _timeAvailability,
        string memory _rating
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyPermissioned(msg.sender) {
        // ensure the account has a Proof of Identity NFT
        if (doctors[_doctorAddress].doctorAddress != address(0))
            revert MediChainPOI__DoctorAlreadyExists();
        if (_perSession <= 0) revert MediChainPOI__AmountMustNotBeZero();

        doctors[_doctorAddress].doctorAddress = _doctorAddress;
        doctors[_doctorAddress].specialty = _specialty;
        doctors[_doctorAddress].perSession = _perSession;
        doctors[_doctorAddress].timeAvailability = _timeAvailability;
        doctors[_doctorAddress].rating = _rating;
        allDoctors.push(_doctorAddress);
        emit DoctorAdded(_doctorAddress, _specialty);
    }

    /**
     * @notice Allows permissioned owners to remove a doctor.
     *
     * @dev Function to remove a doctor.
     * @param _doctorAddress Address of doctor.
     *
     * @dev
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     * May emit an `DoctorRemoved` event.
     */

    function removeDoctor(
        address _doctorAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyPermissioned(msg.sender) {
        if (doctors[_doctorAddress].doctorAddress == address(0))
            revert MediChainPOI__DoctorNotFounded();

        delete doctors[_doctorAddress];
        for (uint256 i = 0; i < allDoctors.length; i++) {
            if (allDoctors[i] == _doctorAddress) {
                allDoctors[i] = allDoctors[allDoctors.length - 1];
                allDoctors.pop();
                break;
            }
        }
        emit DoctorRemoved(_doctorAddress);
    }

    /**
     * @notice Allows permissioned owners to add a new admin.
     *
     * @dev Function to add a new admon.
     * @param _adminAddress Address of admin.
     *
     * @dev
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     * May emit an `AdminAdded` event.
     */

    function addAdmin(
        address _adminAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyPermissioned(msg.sender) {
        if (admins[_adminAddress].adminAddress != address(0))
            revert MediChainPOI__AdminAlreadyExists();
        admins[_adminAddress] = Admin(_adminAddress);
        allAdmins.push(_adminAddress);
        emit AdminAdded(_adminAddress);
    }

    /**
     * @notice Allows permissioned owners to remove admin.
     *
     * @dev Function to remove admon.
     * @param _adminAddress Address of admin.
     *
     * @dev
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     * May emit en `AdminRemoved` event.
     */

    function removeAdmin(
        address _adminAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) onlyPermissioned(msg.sender) {
        if (admins[_adminAddress].adminAddress == address(0))
            revert MediChainPOI__AdminNotFounded();

        delete admins[_adminAddress];
        for (uint256 i = 0; i < allAdmins.length; i++) {
            if (allAdmins[i] == _adminAddress) {
                allAdmins[i] = allAdmins[allAdmins.length - 1];
                allAdmins.pop();
                break;
            }
        }
        emit AdminRemoved(_adminAddress);
    }

    /**
     * @dev Function to get all admin addresses.
     * @return Array of admin addresses.
     */
    function getAllAdmins() external view returns (address[] memory) {
        return allAdmins;
    }

    /**
     * @dev Function to get all doctor addresses.
     * @return Array of doctor addresses.
     */
    function getAllDoctors() external view returns (address[] memory) {
        return allDoctors;
    }

    /**
     * @notice Allows permissioned patients to request a new medical report.
     *
     * @dev Function for a patient to request a medical report from a doctor.
     * @param _doctorAddress Address of the doctor.
     * @param _dateOfBirth Date of birth of the patient.
     * @param _patientCondition Condition description provided by the patient.
     *
     * @dev
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     * May emit an `MedicalReportRequested` event.
     */

    function requestMedicalReport(
        address _doctorAddress,
        uint256 _dateOfBirth,
        string memory _patientCondition
    ) external payable onlyPermissioned(msg.sender) {
        if (doctors[_doctorAddress].doctorAddress == address(0))
            revert MediChainPOI__DoctorNotFounded();

        if (msg.value != doctors[_doctorAddress].perSession)
            revert MediChainPOI__AmountMustMatch();

        Patient storage patient = patients[msg.sender];
        reportCount++;

        MedicalReport storage newReport = medicalReports[reportCount];
        newReport.reportId = reportCount;
        newReport.issueDate = block.timestamp;
        newReport.doctorAddress = _doctorAddress;
        newReport.patientAddress = msg.sender;
        newReport.summary = "";
        newReport.amount += msg.value;
        newReport.paid = true;
        newReport.patientCondition = _patientCondition;

        if (patient.patientAddress == address(0)) {
            patient.patientAddress = msg.sender;
            patient.dateOfBirth = _dateOfBirth;
            patient.lastVisitDate = block.timestamp;
        }

        emit MedicalReportRequested(reportCount, msg.sender, msg.value);
    }

    /**
     * @notice Allows permissioned doctors to submit a medical report.
     *
     * @dev Function for a doctor to submit a medical report.
     * @param _reportId ID of the medical report.
     * @param _summary Summary of the medical report.
     *
     * @dev
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     * May emit an `MedicalReportSubmitted` event.
     */
    function submitMedicalReport(
        uint256 _reportId,
        string memory _summary
    ) public onlyRole(DOCTOR_ROLE) onlyPermissioned(msg.sender) {
        MedicalReport storage report = medicalReports[_reportId];

        if (report.reportId != _reportId)
            revert MediChainPOI__ReportNotFounded();
        if (report.patientAddress == address(0))
            revert MediChainPOI__PatientNotFounded();

        report.submittedReport = true;
        report.issueDate = block.timestamp;
        report.summary = _summary;

        emit MedicalReportSubmitted(_reportId, msg.sender);
    }

    /**
     * @notice Allows permissioned doctors to withdraw funds to their account.
     *
     * @dev Function for a doctor to withdraw the payment for a submitted medical report.
     * @param _reportID ID of the medical report.
     * @return True if transfer succeeded, false otherwise.
     *
     * @dev
     * May revert with `MediChainPOI__NoIdentityNFT`.
     * May revert with `MediChainPOI__Suspended`.
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     *
     */
    function withdraw(
        uint256 _reportID
    )
        external
        onlyRole(DOCTOR_ROLE)
        onlyPermissioned(msg.sender)
        returns (bool)
    {
        if (medicalReports[_reportID].doctorAddress != msg.sender)
            revert MediChainPOI__OnlyDoctorCanWithdraw();

        if (
            !(medicalReports[_reportID].paid &&
                medicalReports[_reportID].submittedReport)
        ) revert MediChainPOI__InvalidWithdrawalConditions();

        medicalReports[_reportID].amount = 0;

        (bool success, ) = payable(msg.sender).call{
            value: medicalReports[_reportID].amount
        }("");
        return success;
    }

    /**
     * @notice Returns the competency rating threshold.
     * @return The competency rating threshold.
     */
    function getCompetencyRatingThreshold() external view returns (uint256) {
        return _competencyRatingThreshold;
    }

    /**
     * @notice Returns the address of the Proof of Identity contract.
     * @return The Proof of Identity address.
     */
    function poiAddress() external view returns (address) {
        return address(_proofOfIdentity);
    }

    /**
     * @notice Returns if a given account has permission to request/submit the `medical report`.
     *
     * @param account The account to check.
     *
     * @return True if the account can request/submit the `medical report`, false otherwise.
     *
     * @dev Requires that the account:
     * -    has a Proof of Identity NFT;
     * -    is not suspended; and
     * -    has established a sufficiently high competency rating and it is not
     *      expired.
     */
    function canSet(address account) external view returns (bool) {
        if (!_hasID(account)) return false;
        if (_isSuspended(account)) return false;
        if (!_checkCompetencyRating(account)) return false;
        return true;
    }

    /* Public
    ========================================*/

    /**
     * @notice Sets the Proof of Identity contract address.
     * @param poi The address for the Proof of Identity contract.
     * @dev May revert with:
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     * May revert with `MediChainPOI__ZeroAddress`.
     * May emit a `POIAddressUpdated` event.
     */
    function setPOIAddress(address poi) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (poi == address(0)) revert MediChainPOI__ZeroAddress();

        _proofOfIdentity = IProofOfIdentity(poi);
        emit POIAddressUpdated(poi);
    }

    /**
     * @notice Sets the Proof of Identity contract address.
     * @param threshold The competency rating threshold.
     * @dev May revert with:
     *  /^AccessControl: account (0x[0-9a-f]{40}) is missing role (0x[0-9a-f]{64})$/
     * May emit a `CompetencyRatingThresholdUpdated` event.
     */
    function setCompetencyRatingThreshold(
        uint256 threshold
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _competencyRatingThreshold = threshold;
        emit CompetencyRatingThresholdUpdated(threshold);
    }

    /* Private
    ========================================*/
    /**
     * @notice Helper function to check whether a given `account`'s competency
     * rating is valid.
     *
     * @param account The account to check.
     *
     * @return True if the check is valid, otherwise false.
     *
     * @dev For a competency rating to be valid, it must:
     * -    not be expired; and
     * -    be greater than, or equal to, the competency rating threshold.
     */
    function _checkCompetencyRating(
        address account
    ) private view returns (bool) {
        (uint256 rating, uint256 expiry, ) = _proofOfIdentity
            .getCompetencyRating(account);

        if (!_validateExpiry(expiry)) return false;
        return rating >= _competencyRatingThreshold;
    }

    /**
     * @notice Similar to `_checkCompetencyRating`, but rather than returning a
     * `bool`, will revert if the check fails.
     *
     * @param account The account to check.
     *
     * @dev For a competency rating to be valid, it must:
     * -    not be expired; and
     * -    be greater than, or equal to, the competency rating threshold.
     *
     * May revert with `MediChainPOI__CompetencyRating`.
     * May revert with `MediChainPOI__AttributeExpired`.
     */
    function _checkCompetencyRatingExn(address account) private view {
        (uint256 rating, uint256 expiry, ) = _proofOfIdentity
            .getCompetencyRating(account);

        if (rating < _competencyRatingThreshold) {
            revert MediChainPOI__CompetencyRating(
                rating,
                _competencyRatingThreshold
            );
        }

        if (!_validateExpiry(expiry)) {
            revert MediChainPOI__AttributeExpired("competencyRating", expiry);
        }
    }

    /**
     * @notice Validates that a given `expiry` is greater than the current
     * `block.timestamp`.
     *
     * @param expiry The expiry to check.
     *
     * @return True if the expiry is greater than the current timestamp, false
     * otherwise.
     */
    function _validateExpiry(uint256 expiry) private view returns (bool) {
        return expiry > block.timestamp;
    }

    /**
     * @notice Returns whether an account holds a Proof of Identity NFT.
     * @param account The account to check.
     * @return True if the account holds a Proof of Identity NFT, else false.
     */
    function _hasID(address account) private view returns (bool) {
        return _proofOfIdentity.balanceOf(account) > 0;
    }

    /**
     * @notice Returns whether an account is suspended.
     * @param account The account to check.
     * @return True if the account is suspended, false otherwise.
     */
    function _isSuspended(address account) private view returns (bool) {
        return _proofOfIdentity.isSuspended(account);
    }
}
