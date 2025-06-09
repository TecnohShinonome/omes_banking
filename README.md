# OMES Banking System

Showcase: https://youtu.be/4Ei3ub9WfrE

Discord: https://discord.gg/dATEunPQ2t

A comprehensive banking system for FiveM servers that supports both ESX and QB Core frameworks.

## Features

- **Framework Compatibility**: Supports both ESX and QB Core frameworks
- **Banking Operations**: Deposit, withdraw, and transfer money
- **Savings Accounts**: Open and manage savings accounts
- **ATM Support**: Use ATMs with PIN verification
- **Transaction History**: Track all banking transactions
- **Balance Charts**: Visual representation of balance history
- **Notification System**: Supports ESX, QB Core, and OX Lib notifications
- **Multi-language Support**: Configurable locale system

## Installation

1. Download and place the resource in your `resources` folder
2. Add `ensure omes_banking` to your `server.cfg`
3. Import the SQL file to create the required database tables
4. Configure the script in `config.lua`

## Configuration

### Framework Selection

In `config.lua`, set your framework:

```lua
Config.Framework = 'esx' -- Options: 'esx', 'qb'
```

### Notification System

Choose your notification system:

```lua
Config.NotificationType = 'ox' -- Options: 'esx', 'ox'
```

### Banking Settings

Configure banking limits and features:

```lua
Config.Banking = {
    enableATM = true,
    enableBankerPed = true,
    enableNUI = true,
    defaultAccount = 'bank',
    maxTransferAmount = 1000000,
    minTransferAmount = 1,
    transferFee = 0, -- Percentage fee for transfers (0 = no fee)
    enableTransactionHistory = true,
    maxHistoryEntries = 50
}
```

## Database Tables

The script requires the following database tables:

```sql
-- Banking transactions
CREATE TABLE IF NOT EXISTS `banking_transactions` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) NOT NULL,
    `type` varchar(50) NOT NULL,
    `amount` int(11) NOT NULL,
    `description` text,
    `date` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`)
);

-- Banking savings accounts
CREATE TABLE IF NOT EXISTS `banking_savings` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) NOT NULL,
    `balance` int(11) NOT NULL DEFAULT 0,
    `status` varchar(20) NOT NULL DEFAULT 'active',
    PRIMARY KEY (`id`)
);

-- Banking PINs
CREATE TABLE IF NOT EXISTS `banking_pins` (
    `id` int(11) NOT NULL AUTO_INCREMENT,
    `identifier` varchar(50) NOT NULL,
    `pin` varchar(4) NOT NULL,
    PRIMARY KEY (`id`)
);
```

## Framework Compatibility

### ESX Legacy
- Uses `identifier` for player identification
- Money management through ESX account system
- ESX notification system support

### QB Core
- Uses `citizenid` for player identification
- Money management through QB Core money system
- QB Core notification system support

## Commands

- `/bank` - Opens the banking interface (admin/testing)

## Dependencies

- **ESX Legacy** (if using ESX framework)
- **QB Core** (if using QB Core framework)
- **OX Lib** (optional, for enhanced notifications)
- **MySQL-Async** or **oxmysql**

## Support

For support and updates, please visit our GitHub repository or Discord server.

## License

This project is licensed under the MIT License. 
