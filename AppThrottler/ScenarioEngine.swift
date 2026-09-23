import Foundation

// MARK: - Scenario Step

struct ScenarioStep: Identifiable, Codable {
    let id: String
    var name: String
    var config: ThrottleConfig
    var durationSeconds: Int

    init(name: String, config: ThrottleConfig, durationSeconds: Int) {
        self.id = UUID().uuidString
        self.name = name
        self.config = config
        self.durationSeconds = durationSeconds
    }
}

// MARK: - Scenario

struct TestScenario: Identifiable, Codable, Hashable {
    let id: String
    var name: String
    var steps: [ScenarioStep]
    var loopCount: Int  // 0 = infinite

    init(name: String, steps: [ScenarioStep], loopCount: Int = 1) {
        self.id = UUID().uuidString
        self.name = name
        self.steps = steps
        self.loopCount = loopCount
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: TestScenario, rhs: TestScenario) -> Bool { lhs.id == rhs.id }
}

// MARK: - Built-in Scenarios

extension TestScenario {
    static let builtIn: [TestScenario] = [
        TestScenario(name: "网络波动模拟", steps: [
            ScenarioStep(name: "正常网络", config: ThrottleConfig(), durationSeconds: 5),
            ScenarioStep(name: "变慢", config: ThrottleConfig(downloadKbps: 500, uploadKbps: 200, latencyMs: 200), durationSeconds: 5),
            ScenarioStep(name: "极慢", config: ThrottleConfig(downloadKbps: 50, uploadKbps: 20, latencyMs: 1000, packetLoss: 0.1), durationSeconds: 5),
            ScenarioStep(name: "恢复", config: ThrottleConfig(), durationSeconds: 5),
        ], loopCount: 3),

        TestScenario(name: "断网恢复测试", steps: [
            ScenarioStep(name: "正常", config: ThrottleConfig(), durationSeconds: 5),
            ScenarioStep(name: "断网", config: ThrottleConfig(downloadKbps: 1, uploadKbps: 1, latencyMs: 10000, packetLoss: 0.99), durationSeconds: 5),
            ScenarioStep(name: "恢复中", config: ThrottleConfig(downloadKbps: 500, uploadKbps: 200, latencyMs: 300, packetLoss: 0.2), durationSeconds: 5),
            ScenarioStep(name: "完全恢复", config: ThrottleConfig(), durationSeconds: 5),
        ], loopCount: 2),

        TestScenario(name: "弱网渐变", steps: [
            ScenarioStep(name: "良好", config: ThrottleConfig(downloadKbps: 10000, uploadKbps: 5000), durationSeconds: 3),
            ScenarioStep(name: "一般", config: ThrottleConfig(downloadKbps: 2000, uploadKbps: 1000, latencyMs: 100, packetLoss: 0.02), durationSeconds: 3),
            ScenarioStep(name: "较差", config: ThrottleConfig(downloadKbps: 500, uploadKbps: 200, latencyMs: 300, packetLoss: 0.05), durationSeconds: 3),
            ScenarioStep(name: "很差", config: ThrottleConfig(downloadKbps: 100, uploadKbps: 50, latencyMs: 800, packetLoss: 0.15), durationSeconds: 3),
            ScenarioStep(name: "极差", config: ThrottleConfig(downloadKbps: 10, uploadKbps: 5, latencyMs: 2000, packetLoss: 0.40), durationSeconds: 3),
        ], loopCount: 2),

        TestScenario(name: "丢包递增测试", steps: [
            ScenarioStep(name: "0% 丢包", config: ThrottleConfig(), durationSeconds: 5),
            ScenarioStep(name: "5% 丢包", config: ThrottleConfig(packetLoss: 0.05), durationSeconds: 5),
            ScenarioStep(name: "10% 丢包", config: ThrottleConfig(packetLoss: 0.10), durationSeconds: 5),
            ScenarioStep(name: "20% 丢包", config: ThrottleConfig(packetLoss: 0.20), durationSeconds: 5),
            ScenarioStep(name: "40% 丢包", config: ThrottleConfig(packetLoss: 0.40), durationSeconds: 5),
        ], loopCount: 1),
    ]
}

// MARK: - Scenario Engine

@MainActor
class ScenarioEngine: ObservableObject {
    @Published var isRunning = false
    @Published var currentScenarioName = ""
    @Published var currentStepName = ""
    @Published var currentStepIndex = 0
    @Published var totalSteps = 0
    @Published var remainingSeconds = 0
    @Published var currentLoop = 0
    @Published var totalLoops = 0

    private var throttleManager: ThrottleManager
    private var targetApp: AppProcess?
    private var scenarioTask: Task<Void, Never>?

    init(throttleManager: ThrottleManager) {
        self.throttleManager = throttleManager
    }

    func start(scenario: TestScenario, app: AppProcess) {
        stop()

        targetApp = app
        isRunning = true
        currentScenarioName = scenario.name
        totalSteps = scenario.steps.count
        totalLoops = scenario.loopCount

        scenarioTask = Task { [weak self] in
            await self?.runScenario(scenario)
        }
    }

    func stop() {
        scenarioTask?.cancel()
        scenarioTask = nil
        isRunning = false
        currentStepName = ""
        currentStepIndex = 0
        remainingSeconds = 0
        currentLoop = 0

        // Remove throttle on stop
        if let app = targetApp {
            throttleManager.removeThrottle(app: app)
        }
    }

    private func runScenario(_ scenario: TestScenario) async {
        let loops = scenario.loopCount == 0 ? Int.max : scenario.loopCount
        var loopIteration = 0

        while loopIteration < loops && !Task.isCancelled {
            loopIteration += 1
            currentLoop = loopIteration

            for (index, step) in scenario.steps.enumerated() {
                guard !Task.isCancelled else { break }

                currentStepIndex = index + 1
                currentStepName = step.name
                remainingSeconds = step.durationSeconds

                // Apply the step config
                if let app = targetApp {
                    throttleManager.applyThrottle(app: app, config: step.config)
                }

                // Wait for duration
                for second in stride(from: step.durationSeconds, through: 1, by: -1) {
                    guard !Task.isCancelled else { break }
                    remainingSeconds = second
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
            }
        }

        // Done
        if !Task.isCancelled, let app = targetApp {
            throttleManager.removeThrottle(app: app)
        }
        isRunning = false
    }
}
