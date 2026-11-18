// ignore_for_file: public_member_api_docs
/// Sync state of a row.
enum SyncStatus { pending, synced, conflict }

/// Unit occupancy.
enum UnitStatus { vacant, occupied, maintenance }

/// Tenant lifecycle.
enum TenantStatus { active, notice, vacated }

/// Lease lifecycle.
enum LeaseStatus { active, expiring, expired, renewed }

/// How a payment was made (recorded manually; no payment integration).
enum PaymentMethod { cash, bkash, nagad, rocket, bank, qr }

/// What a payment pays for.
enum PaymentType { rent, utility, advance, partial, deposit, lateFee }

/// Payment state.
enum PaymentStatus { paid, partial, pending, advance }

/// Monthly bill state. "sent" means WhatsApp was opened by a person.
enum BillStatus { generated, sent, partial, paid, cancelled }

/// Line type on a bill.
enum BillItemKind { rent, serviceCharge, utility, lateFee, carriedForward, advanceCredit, other }

/// Expense category.
enum ExpenseCategory { repair, tax, commission, utility, salary, other }

/// Maintenance ticket state.
enum TicketStatus { open, inProgress, resolved, closed }

/// Stored document type.
enum DocumentType { lease, nid, receipt, bill, photo, clearance, policeForm, legalNotice, noc }

/// Person type in a tenant's household.
enum HouseholdType { family, domesticWorker, driver, guard, other }

/// Metered utility.
enum UtilityKind { electricity, gas, water }

/// Late fee calculation style.
enum LateFeeType { fixed, percent, perDay }

/// Invitation state.
enum InvitationStatus { pending, accepted, expired, cancelled }

/// Deletion request state.
enum DeletionRequestStatus { pending, approved, rejected }

/// Deposit state.
enum DepositStatus { held, adjusted, refunded }

/// What an OCR scan came from.
enum OcrSourceType { nid, lease, paymentScreenshot, ledger }

/// Permanent legal record type.
enum LegalRecordKind { legalNotice, noc }

/// Sync channel: basic data or vault (sensitive) data.
enum SyncChannel { basic, vault }

/// Sync record direction.
enum SyncDirection { outbox, inbox }

/// Where a sync record is in its life.
enum SyncOpState { pending, sent, acknowledged, applied, rejected }

/// Optional extra charge types added on top of rent. Nothing here is mandatory.
enum ChargeKind { electricity, gas, water, internet, fine, damage, other }
