import Foundation

@MainActor
final class DependencyContainer: ObservableObject {
    lazy var databaseManager: DatabaseManager = { DatabaseManager() }()
    lazy var supabaseClient: SupabaseClient = { SupabaseClient(url: Configuration.supabaseURL, anonKey: Configuration.supabaseAnonKey) }()
    lazy var authManager: AuthManager = { AuthManager(supabaseClient: supabaseClient) }()
    lazy var syncCoordinator: SyncCoordinator = { SyncCoordinator(databaseManager: databaseManager, supabaseClient: supabaseClient) }()
    lazy var notificationManager: NotificationManager = { NotificationManager() }()
    lazy var watchSessionManager: WatchSessionManager = { WatchSessionManager.shared }()
    lazy var subscriptionManager: SubscriptionManager = { SubscriptionManager(supabaseClient: supabaseClient) }()
    lazy var siriShortcutsService: SiriShortcutsService = { let s = SiriShortcutsService.shared; s.configure(databaseManager: databaseManager, notificationManager: notificationManager); return s }()
    lazy var handoffService: HandoffService = { HandoffService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator) }()
    lazy var taskService: TaskService = { TaskService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator) }()
    lazy var binderService: BinderService = { BinderService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator) }()
    lazy var exportService: ExportService = { ExportService(supabaseClient: supabaseClient) }()
    lazy var coachService: CoachService = { CoachService(supabaseClient: supabaseClient, databaseManager: databaseManager) }()
    lazy var appointmentQuestionService: AppointmentQuestionService = { AppointmentQuestionService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator, authManager: authManager) }()
    lazy var dischargeWizardService: DischargeWizardService = { DischargeWizardService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator, taskService: taskService, subscriptionManager: subscriptionManager) }()
    lazy var wellnessService: WellnessService = { WellnessService(supabaseClient: supabaseClient, databaseManager: databaseManager) }()
    lazy var appleCalendarProvider: AppleCalendarProvider = { AppleCalendarProvider() }()
    lazy var calendarSyncService: CalendarSyncService = { CalendarSyncService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator, appleProvider: appleCalendarProvider) }()
    lazy var icalFeedService: ICalFeedService = { ICalFeedService(databaseManager: databaseManager, supabaseClient: supabaseClient) }()
    lazy var documentScannerService: DocumentScannerService = { DocumentScannerService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator, authManager: authManager) }()
    lazy var communicationLogService: CommunicationLogService = { CommunicationLogService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator, subscriptionManager: subscriptionManager, authManager: authManager, taskService: taskService) }()
    lazy var familyMeetingService: FamilyMeetingService = { FamilyMeetingService(supabaseClient: supabaseClient) }()
    lazy var transportationService: TransportationService = { TransportationService(supabaseClient: supabaseClient, subscriptionManager: subscriptionManager, authManager: authManager) }()
    lazy var journalService: JournalService = { JournalService(databaseManager: databaseManager, supabaseClient: supabaseClient, syncCoordinator: syncCoordinator, authManager: authManager) }()
    lazy var videoService: VideoService = { VideoService(databaseManager: databaseManager, supabaseClient: supabaseClient, subscriptionManager: subscriptionManager, authManager: authManager, syncCoordinator: syncCoordinator) }()
    lazy var videoCompressionService: VideoCompressionService = { VideoCompressionService() }()
    lazy var translationService: TranslationService = { TranslationService(supabaseClient: supabaseClient, subscriptionManager: subscriptionManager, databaseManager: databaseManager) }()
    lazy var legalVaultService: LegalVaultService = { LegalVaultService(databaseManager: databaseManager, supabaseClient: supabaseClient, subscriptionManager: subscriptionManager, authManager: authManager) }()
    lazy var careCostService: CareCostService = { CareCostService(databaseManager: databaseManager, supabaseClient: supabaseClient, subscriptionManager: subscriptionManager) }()
    lazy var respiteFinderService: RespiteFinderService = { RespiteFinderService(supabaseClient: supabaseClient, subscriptionManager: subscriptionManager, authManager: authManager) }()
    init() { do { try databaseManager.setup() } catch { fatalError("Failed to setup database: \(error)") } }
}

enum Configuration {
    // Local Supabase defaults (standard dev JWT — safe to commit)
    private static let localURL = "http://localhost:54321"
    private static let localAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

    // Production credentials loaded from Info.plist (injected via xcconfig or Xcode build settings)
    private static var productionURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
    }
    private static var productionAnonKey: String {
        Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String ?? ""
    }

    static var supabaseURL: URL {
        // 1. Environment variable (CI / testing override)
        if let s = ProcessInfo.processInfo.environment["SUPABASE_URL"], let u = URL(string: s) { return u }
        // 2. Info.plist (production builds via xcconfig)
        if !productionURL.isEmpty, let u = URL(string: productionURL) { return u }
        // 3. Fallback to local dev
        return URL(string: localURL)!
    }

    static var supabaseAnonKey: String {
        if let k = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"] { return k }
        if !productionAnonKey.isEmpty { return productionAnonKey }
        return localAnonKey
    }
}

class HandoffService { let databaseManager: DatabaseManager; let supabaseClient: SupabaseClient; let syncCoordinator: SyncCoordinator; init(databaseManager: DatabaseManager, supabaseClient: SupabaseClient, syncCoordinator: SyncCoordinator) { self.databaseManager = databaseManager; self.supabaseClient = supabaseClient; self.syncCoordinator = syncCoordinator } }
class TaskService { let databaseManager: DatabaseManager; let supabaseClient: SupabaseClient; let syncCoordinator: SyncCoordinator; init(databaseManager: DatabaseManager, supabaseClient: SupabaseClient, syncCoordinator: SyncCoordinator) { self.databaseManager = databaseManager; self.supabaseClient = supabaseClient; self.syncCoordinator = syncCoordinator } }
class BinderService { let databaseManager: DatabaseManager; let supabaseClient: SupabaseClient; let syncCoordinator: SyncCoordinator; init(databaseManager: DatabaseManager, supabaseClient: SupabaseClient, syncCoordinator: SyncCoordinator) { self.databaseManager = databaseManager; self.supabaseClient = supabaseClient; self.syncCoordinator = syncCoordinator } }
class ExportService { let supabaseClient: SupabaseClient; init(supabaseClient: SupabaseClient) { self.supabaseClient = supabaseClient } }
