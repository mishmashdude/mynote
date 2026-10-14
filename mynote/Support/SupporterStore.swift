import Observation
import StoreKit

/// The one-off "Supporter" purchase that unlocks every theme. No subscription:
/// pay once and it's yours for good, restorable on any of your devices.
@Observable
@MainActor
final class SupporterStore {
    static let shared = SupporterStore()

    /// Create this in App Store Connect as a Non-Consumable at the 1.99 USD price.
    static let productID = "com.andi.mynote.supporter"

    enum Outcome: Equatable {
        case purchased
        case cancelled
        /// Waiting on something outside the app, e.g. Ask to Buy.
        case pending
        case failed(String)
    }

    private(set) var product: Product?
    private(set) var isPurchasing = false
    private(set) var isRestoring = false

    @ObservationIgnored private var updates: Task<Void, Never>?
    /// Only the newest entitlement check may change the answer.
    @ObservationIgnored private var checkGeneration = 0

    private init() {}

    var isSupporter: Bool { AppSettings.shared.isSupporter }
    /// The local price, once the App Store has said what it is (prices differ by country).
    var displayPrice: String? {
        #if DEBUG
        // simctl launches have no StoreKit configuration, so screenshot runs pass the price in.
        if product == nil, let price = DebugSeeding.priceOverride { return price }
        #endif
        return product?.displayPrice
    }

    /// Call once at launch: listens for purchases made elsewhere (other devices, Ask to Buy,
    /// refunds) and checks what this Apple Account already owns.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                // One transaction can be a family member's copy; ask about everything owned instead.
                await self?.refreshEntitlement()
            }
        }
        Task {
            await refreshEntitlement()
            await loadProduct()
        }
    }

    func loadProduct() async {
        guard product == nil else { return }
        product = try? await Product.products(for: [Self.productID]).first
    }

    func purchase() async -> Outcome {
        guard !isPurchasing else { return .cancelled }
        isPurchasing = true
        defer { isPurchasing = false }
        await loadProduct()
        guard let product else {
            return .failed("The App Store isn't reachable right now. Check your connection and try again.")
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    return .failed("Apple couldn't confirm this purchase. Try Restore Purchase in a moment.")
                }
                await transaction.finish()
                checkGeneration += 1
                setSupporter(true)
                return .purchased
            case .userCancelled:
                return .cancelled
            case .pending:
                return .pending
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Asks the App Store for past purchases. Returns true when the unlock was found.
    func restore() async -> Bool {
        isRestoring = true
        defer { isRestoring = false }
        try? await AppStore.sync()
        await refreshEntitlement()
        return isSupporter
    }

    private func refreshEntitlement() async {
        checkGeneration += 1
        let generation = checkGeneration
        var owned = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result, transaction.productID == Self.productID, transaction.revocationDate == nil {
                owned = true
            }
        }
        // A newer check (or a purchase) finished first: its answer stands.
        guard generation == checkGeneration else { return }
        #if DEBUG
        // Screenshot runs pick the state with a launch argument.
        if DebugSeeding.supporterOverride != nil { return }
        #endif
        setSupporter(owned)
    }

    private func setSupporter(_ owned: Bool) {
        let settings = AppSettings.shared
        if settings.isSupporter != owned { settings.isSupporter = owned }
        // StoreKit has answered. A theme saved back when every theme was free, and not one
        // this person was allowed to keep, is replaced so nothing outside the app still reads it.
        if !owned { settings.replaceLockedThemePicks() }
    }
}
