# Example messages

Every sample message the packs are tested with, generated from `packs/*/fixtures.yaml` by `tool/message_examples.dart`. Do not edit; regenerate with `dart run tool/message_examples.dart`.

All samples are synthetic: fake names, masked fake numbers and made-up receipts, written in the shape of real alerts. "Review inbox" means no rule reads the message, so the person checks it once.

- [Airtel Money](#airtel-money)
- [Equity Bank](#equity-bank)
- [I&M Bank](#im-bank)
- [KCB](#kcb)
- [Loop](#loop)
- [M-Pesa](#m-pesa)

## Airtel Money

Pack `airtel_money` 0.1.0 · senders `AirtelMoney` · rules none yet (review-only)

**a send goes to the review inbox** (`AirtelMoney` → review inbox)

```text
Example alert: Ksh 500.00 sent to JANE DOE 0700000001 on 26/10/2026 at 09:15. Balance Ksh 1,500.00. TID EX0000000001.
```

**the sender is matched in any case** (`AIRTELMONEY` → review inbox)

```text
Example alert: Ksh 1,000.00 received from JOHN KAMAU 0700000002 on 26/10/2026 at 10:02. Balance Ksh 2,500.00. TID EX0000000002.
```

## Equity Bank

Pack `equity` 0.1.0 · senders `Equity Bank`, `EQUITYBANK`, `EQUITY_BANK` · rules `wallet_transfer`, `received`

**send to a mobile wallet** (`Equity Bank` → `wallet_transfer` · money out)

```text
Your transaction of Kshs. 200.0  has been credited to  254700000001  JANE DOE. Ref.  EQA0000000000001. MPESA Ref.  TJA0000001 on  26/10/2026 at 09:15:30.
```

**receive into the account** (`EQUITYBANK` → `received` · money in)

```text
You have received 2000.00 KES from EXAMPLE TRADERS 0********1111 to your Equity account 0********1234. Ref. EQB0000000000002 on 12 Sep 2026 at 14:05 EAT
```

**service notice goes to the review inbox** (`EQUITY_BANK` → review inbox)

```text
Dear Customer, Equity mobile banking will be briefly unavailable tonight from 11:00 PM for planned maintenance.
```

## I&M Bank

Pack `im_bank` 0.1.0 · senders `I&M` · rules `account_alert`

**account debited** (`I&M` → `account_alert` · money out)

```text
Dear Customer, your account 0000****001 has been debited with KES 2,500.00 on 26-Oct-2026 14:05. Ref: IMB000000001. Avail. bal KES 10,000.00.
```

**account credited** (`I&M` → `account_alert` · money in)

```text
Dear Customer, your account 0000****001 has been credited with KES 45,000.00 on 28-Oct-2026 08:30. Ref: IMB000000002. Avail. bal KES 55,000.00.
```

## KCB

Pack `kcb` 0.2.0 · senders `KCB` · rules `account_alert`, `wallet_transfer`, `account_named`

**account debited** (`KCB` → `account_alert` · money out)

```text
Dear Customer, KES 3,000.00 has been debited from your account ****0001 on 26/10/2026 at 15:20. Transaction Ref: KCB0000000001. Your available balance is KES 7,000.00.
```

**account credited** (`KCB` → `account_alert` · money in)

```text
Dear Customer, KES 12,500.50 has been credited to your account ****0001 on 27/10/2026 at 09:00. Transaction Ref: KCB0000000002. Your available balance is KES 19,500.50.
```

**send to a mobile wallet** (`KCB` → `wallet_transfer` · money out)

```text
KCB0000000000003  KES 1,000.00 sent from 123****456 to 254****789 - JANE DOE on 2026-10-26 09:15:00 AM. M-PESA REF: TJA0000001
```

**named account credited** (`KCB` → `account_named` · money in)

```text
Dear JANE, your KCB A/C ****1234 has been credited with KES 2,000.00 from JOHN KAMAU on 26/10/2026 at 9:15 PM. Ref: KCB0000000004. Avail Bal KES 9,000.00
```

**balance enquiry goes to the review inbox** (`KCB` → review inbox)

```text
Dear Customer, your account balance is KES 19,500.50 as at 27/10/2026 10:00.
```

## Loop

Pack `loop` 0.1.0 · senders `NCBALOOP`, `NCBA_LOOP` · rules none yet (review-only)

**a payment alert goes to the review inbox** (`NCBALOOP` → review inbox)

```text
Example alert: KES 1,000.00 paid to EXAMPLE STORES on 26/10/2026 at 09:15. Ref EX00000001.
```

**the other sender ID is read too** (`NCBA_LOOP` → review inbox)

```text
Example alert: KES 2,500.00 received from JANE DOE on 26/10/2026 at 10:02. Ref EX00000002.
```

## M-Pesa

Pack `mpesa` 0.2.0 · senders `MPESA` · rules `paybill`, `sent`, `received`, `till`, `withdrawal`, `airtime`, `fuliza`, `fuliza_repayment`, `reversal`, `mshwari_deposit`, `mshwari_withdraw`, `airtime_other`, `deposit`

**send money to a person** (`MPESA` → `sent` · money out)

```text
TJA0000001 Confirmed. Ksh1,500.00 sent to JANE DOE 0700***001 on 26/10/26 at 9:15 AM. New M-PESA balance is Ksh3,250.00. Transaction cost, Ksh15.00. Amount you can transact within the day is 498,500.00.
```

**pay a bill** (`MPESA` → `paybill` · money out)

```text
TJA0000002 Confirmed. Ksh1,200.00 sent to EXAMPLE POWER LTD for account 1234567890 on 26/10/26 at 11:30 AM New M-PESA balance is Ksh2,035.00. Transaction cost, Ksh15.00.Amount you can transact within the day is 497,300.00.
```

**receive money from a person** (`MPESA` → `received` · money in)

```text
TJA0000003 Confirmed.You have received Ksh2,000.00 from JOHN KAMAU 0700***002 on 26/10/26 at 10:02 AM  New M-PESA balance is Ksh4,035.00.
```

**receive money from an organisation** (`MPESA` → `received` · money in)

```text
TJA0000010 Confirmed.You have received Ksh5,000.00 from EXAMPLE SACCO on 27/10/26 at 8:05 AM New M-PESA balance is Ksh8,904.50.
```

**pay a till** (`MPESA` → `till` · money out)

```text
TJA0000004 Confirmed. Ksh350.00 paid to EXAMPLE GROCERS. on 26/10/26 at 1:45 PM.New M-PESA balance is Ksh3,685.00. Transaction cost, Ksh0.00. Amount you can transact within the day is 496,950.00.
```

**withdraw cash at an agent** (`MPESA` → `withdrawal` · money out)

```text
TJA0000005 Confirmed.on 26/10/26 at 5:10 PMWithdraw Ksh1,000.00 from 123456 - EXAMPLE AGENT SHOP NAIROBI New M-PESA balance is Ksh2,656.00. Transaction cost, Ksh29.00.
```

**buy airtime** (`MPESA` → `airtime` · money out)

```text
TJA0000006 confirmed.You bought Ksh100.00 of airtime on 26/10/26 at 7:00 PM.New M-PESA balance is Ksh2,556.00. Transaction cost, Ksh0.00.
```

**Fuliza draw uses the received time** (`MPESA` → `fuliza` · money in)

```text
TJA0000007 Confirmed. Fuliza M-Pesa amount is Ksh 150.00. Access Fee charged Ksh 1.50. Total Fuliza M-Pesa outstanding amount is Ksh 151.50 due on 25/11/26. To check daily charges, Dial *000*0#OK Select Query Charges
```

**Fuliza repayment** (`MPESA` → `fuliza_repayment` · money out)

```text
TJA0000008 Confirmed. Ksh 151.50 from your M-PESA has been used to fully pay your outstanding Fuliza M-PESA. Available Fuliza M-PESA limit is Ksh 2,000.00. M-PESA balance is Ksh8,753.00.
```

**reversal of a send** (`MPESA` → `reversal` · money in)

```text
TJA0000009 Confirmed. Reversal of transaction TJA0000001 has been successfully reversed  on 26/10/26 at 8:00 PM and Ksh1,500.00 is credited to your M-PESA account. New M-PESA account balance is Ksh4,056.00.
```

**send with two spaces in the name and no phone** (`MPESA` → `sent` · money out)

```text
TJA0000010 Confirmed. Ksh300.00 sent to MARY  ATIENO on 26/10/26 at 9:20 AM. New M-PESA balance is Ksh2,950.00. Transaction cost, Ksh0.00. Amount you can transact within the day is 498,200.00.
```

**receive from a bank with its short code** (`MPESA` → `received` · money in)

```text
TJA0000011 Confirmed.You have received Ksh5,000.00 from EXAMPLE BANK 1 522522 on 26/10/26 at 10:10 AM New M-PESA balance is Ksh9,035.00.  Separate personal and business funds through Pochi la Biashara on *334#.
```

**receive with a greeting before the receipt** (`MPESA` → `received` · money in)

```text
Congratulations! TJA0000012 confirmed.You have received Ksh800.00 from EXAMPLE WALLET B2C. on 26/10/26 at 10:15 AM.New M-PESA balance is Ksh9,835.00.
```

**deposit cash at an agent** (`MPESA` → `deposit` · money in)

```text
TJA0000013 Confirmed. On 26/10/26 at 2:30 PM Give Ksh2,000.00 cash to EXAMPLE AGENT SHOP New M-PESA balance is Ksh10,806.00.
```

**buy airtime for another number** (`MPESA` → `airtime_other` · money out)

```text
TJA0000014 Confirmed.Ksh50.00 of airtime for 0700000003 on 26/10/26 at 3:05 PM  New M-PESA balance is Ksh10,656.00.
```

**Fuliza draw in capitals** (`MPESA` → `fuliza` · money in)

```text
TJA0000015 Confirmed. Fuliza M-PESA amount is Ksh 250.00. Access Fee charged Ksh 2.50. Total Fuliza M-PESA outstanding amount is Ksh 1794.51 due on 25/11/26. To check daily charges, Dial *334#OK Select Fuliza M-PESA to Query Charges.
```

**move to M-Shwari** (`MPESA` → `mshwari_deposit` · money out)

```text
TJA0000016 Confirmed.Ksh500.00 transferred to M-Shwari account on 26/10/26 at 4:00 PM. M-PESA balance is Ksh247.50 .New M-Shwari saving account balance is Ksh1,500.00. Transaction cost Ksh.0.00
```

**move from M-Shwari** (`MPESA` → `mshwari_withdraw` · money in)

```text
TJA0000017 Confirmed.Ksh200.00 transferred from M-Shwari account on 26/10/26 at 4:10 PM. M-Shwari balance is Ksh1,300.00 .M-PESA balance is Ksh447.50 .Transaction cost Ksh.0.00
```

**reversal taken back from the recipient** (`MPESA` → `reversal` · money out)

```text
TJA0000018  confirmed. Reversal of transaction TJA0000011 has been successfully reversed  on 26/10/26  at 5:00 PM and Ksh300.00 is debited from your M-PESA account. New M-PESA account balance is Ksh147.50.
```

**M-Shwari balance goes to the review inbox** (`MPESA` → review inbox)

```text
TJA0000019 Confirmed . Your M-Shwari Deposit Account balance is Ksh1,300.00 .Transaction cost Ksh 0.00.
```

**service notice goes to the review inbox** (`MPESA` → review inbox)

```text
Dear Customer, M-PESA services will be briefly unavailable tonight from 11:00 PM for planned maintenance.
```
