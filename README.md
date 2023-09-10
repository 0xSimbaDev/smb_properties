# smb_properties
Enhanced property management for FiveM, integrated with QBUS. Enables player property ownership, tenant management, and dynamic interactions.


CREATE TABLE `smb_properties` (
  `propertyName` varchar(255) NOT NULL,
  `propertyType` enum('hotel','motel','mansion','house') NOT NULL,
  `ownerCitizenID` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`propertyName`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

CREATE TABLE `smb_properties_units` (
  `unitID` int NOT NULL,
  `propertyName` varchar(255) NOT NULL,
  `rentCost` int NOT NULL DEFAULT '0',
  `isAvailable` tinyint(1) NOT NULL DEFAULT '1',
  PRIMARY KEY (`propertyName`, `unitID`),
  FOREIGN KEY (`propertyName`) REFERENCES `smb_properties` (`propertyName`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

CREATE TABLE `smb_properties_tenants` (
  `tenantID` int NOT NULL AUTO_INCREMENT,
  `unitID` int NOT NULL,
  `propertyName` varchar(255) NOT NULL,
  `citizenID` varchar(255) NOT NULL,
  `stash_id` varchar(512) UNIQUE DEFAULT NULL,
  `status` enum('active','evicted','completed') NOT NULL DEFAULT 'active',
  `citizenName` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`tenantID`),
  FOREIGN KEY (`propertyName`, `unitID`) REFERENCES `smb_properties_units` (`propertyName`, `unitID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

CREATE TABLE `smb_properties_ledger` (
  `id` int NOT NULL AUTO_INCREMENT,
  `tenantID` int NOT NULL,
  `transactionDate` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `description` varchar(255) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `balance` decimal(10,2) NOT NULL,
  `transactionType` enum('Charge','Payment','Adjustment') NOT NULL,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`tenantID`) REFERENCES `smb_properties_tenants` (`tenantID`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
