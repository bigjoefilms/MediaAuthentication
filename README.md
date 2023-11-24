# MediChainPOI (Proof of Identity)

## Overview

MediChainPOI is an example implementation utilizing the Proof of Identity contract to manage permissioned access to specific features within a healthcare blockchain system. This contract is designed to ensure that only users (Admins, Doctors, and Patients) with established and sufficiently high competency ratings can access certain functionalities.

## Functionality and Roles

- **Admins**:
  - Have the authority to add and remove doctors from the system.
- **Doctors**:
  - Are permitted to add medical reports and withdraw funds as necessary for their services.
- **Patients**:
  - Can request medical reports and make payments to doctors for services rendered.
- **All Users**:
  - Have read permission to access certain functionalities within the contract.

## Purpose

This contract is structured to ensure secure access control and proper handling of sensitive healthcare-related data on a blockchain network. By utilizing the Proof of Identity mechanism, it establishes a competency rating system that regulates access based on user roles, ensuring that only authorized entities can perform specific actions within the healthcare ecosystem.

## Usage

The contract allows for the secure management of healthcare-related functionalities by delineating distinct roles and permissions. Users can interact with the contract according to their roles, enabling efficient management of medical records, payments, and access control while maintaining data integrity and security.
