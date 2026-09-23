import SwiftUI

struct PaywallView: View {
    @ObservedObject var license: LicenseManager

    var body: some View {
        VStack(spacing: 16) {
            Spacer().frame(height: 10)
            Image(systemName: "checkmark.seal.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .foregroundColor(.classicBlue)
                .shadow(radius: 2)
            Text("Numdr License")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(.black)
            VStack(alignment: .leading, spacing: 8) {
                Label("All features included", systemImage: "sparkles")
                Label("One-time purchase (Lemon Squeezy)", systemImage: "checkmark.seal")
                Label("Local processing on your Mac", systemImage: "lock.shield")
            }
            .foregroundColor(.black.opacity(0.8))
            .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("License key")
                    .font(.subheadline.bold())
                    .foregroundColor(.black)
                TextField("Paste your Lemon Squeezy license key", text: $license.licenseKeyInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(license.isBusy)
            }
            .padding(.top, 4)

            Button {
                Task { await license.activateLicense() }
            } label: {
                HStack {
                    if license.isBusy { ProgressView().controlSize(.small) }
                    Text("Activate Key")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.classicBlue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(license.isBusy || license.licenseKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.top, 4)

            Button {
                license.openCheckout()
            } label: {
                Text("Buy License")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.75))
            }
            .buttonStyle(.plain)
            .disabled(license.isBusy)
            .padding(.top, 2)

            if license.hasStoredLicense {
                Button {
                    Task { await license.deactivateLicense() }
                } label: {
                    Text("Deactivate on this Mac")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red.opacity(0.85))
                }
                .buttonStyle(.plain)
                .disabled(license.isBusy)
                .padding(.top, 2)
            }

            if let status = license.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(.green)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            if let error = license.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            Spacer()
            Button {
                license.isPresentingPaywall = false
            } label: {
                Text("Not now")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .padding(24)
        .background(Color.mainCream)
    }
}
