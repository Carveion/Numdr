# Numdr Monetization (Lemon Squeezy License Keys)

Numdr uses a **7-day local trial** plus **Lemon Squeezy license keys**. Feature gating is:

> **trial active OR license valid (including offline grace)**

StoreKit / Apple IAP has been removed.

## What you need in Lemon Squeezy

1. Create (or open) your store at [Lemon Squeezy](https://app.lemonsqueezy.com/).
2. Create a product (one-time is typical for Numdr).
3. Enable **License keys** on the product/variant:
   - Dashboard → Product → License keys
   - Set an activation limit (e.g. 1–3 Macs per key)
4. Copy the **checkout / buy URL** for the variant (Share / Buy link).

## Wire the checkout URL in the app

Edit `Numdr/LicenseManager.swift`:

```swift
static let checkoutURLString = "https://YOUR_STORE.lemonsqueezy.com/checkout/buy/YOUR_VARIANT_ID"
```

Replace with your real Lemon Squeezy checkout URL. **Buy License** in the paywall opens this URL in the browser.

No Lemon Squeezy **API secret** belongs in this repo. The app only calls the public License API endpoints, authenticated by the customer’s license key.

## Public License API used by the app

Base: `https://api.lemonsqueezy.com/v1/licenses`

| Action     | Endpoint     | Body fields                          |
|------------|--------------|--------------------------------------|
| Activate   | `POST /activate`   | `license_key`, `instance_name` |
| Validate   | `POST /validate`   | `license_key`, optional `instance_id` |
| Deactivate | `POST /deactivate` | `license_key`, `instance_id`   |

Headers:

- `Accept: application/json`
- `Content-Type: application/x-www-form-urlencoded`

Docs: https://docs.lemonsqueezy.com/api/license-api

## App behavior

1. **Trial** — `TrialManager` starts a 7-day trial on first launch (`NumdrTrialStartDate` in AppStorage).
2. **Activate** — User pastes a key in the paywall → `LicenseManager.activateLicense` → LS `/activate` → stores:
   - License key in **Keychain** (`com.controlx.Numdr.license`)
   - `instance_id` in UserDefaults (`NumdrLicenseInstanceID`)
   - Last success timestamp (`NumdrLicenseLastValidatedAt`)
3. **Validate** — On launch / refresh, calls `/validate` with key + instance id.
4. **Offline grace** — If validation fails due to network, the app stays licensed for **21 days** after the last successful activate/validate.
5. **Deactivate** — Optional; frees an activation seat via `/deactivate` and clears local Keychain + instance id.
6. **Restore Purchases** — Removed (not applicable to license keys).

## Sandbox / networking

The Xcode target enables **Outgoing Network Connections** so the app can reach `api.lemonsqueezy.com`. PDFs are still processed entirely on-device.

## Testing checklist

- [ ] Fresh install: trial starts; custom labels available during trial
- [ ] After trial ends without a key: gated features locked; paywall can open
- [ ] Paste valid LS test key → Activate → unlocked
- [ ] Quit/relaunch → still unlocked (validate or offline grace)
- [ ] Turn off network within grace → still unlocked
- [ ] Deactivate → locked again (unless trial still active)
- [ ] Buy License opens your checkout URL

## Files

| File | Role |
|------|------|
| `Numdr/TrialManager.swift` | 7-day trial |
| `Numdr/LicenseManager.swift` | LS activate/validate/deactivate + Keychain |
| `Numdr/PaywallView.swift` | Paste key / Activate / Buy / Deactivate |
| `Numdr/ContentView.swift` | App UI + gating (`isProAvailable`) |
