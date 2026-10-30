/**
 * Login Feature API Contract Definitions
 */

const LoginFlowType = Object.freeze({
  PVD: "PVD",
  MF: "MF",
  ODD: "ODD"
});

const AccountType = Object.freeze({
  INDIVIDUAL: "INDIVIDUAL",
  JOINT: "JOINT",
  JURISTIC: "JURISTIC"
});

module.exports = {
  LoginFlowType,
  AccountType
};
