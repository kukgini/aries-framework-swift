// swiftlint:disable force_cast

import XCTest
@testable import AriesFramework

class ConnectionlessExchangeTest: XCTestCase {
    var faberAgent: Agent!
    var aliceAgent: Agent!
    var credDefId: String!
    var faberConnection: ConnectionRecord!
    var aliceConnection: ConnectionRecord!

    let credentialPreview = CredentialPreview.fromDictionary([
        "name": "John",
        "age": "99"
    ])
    let receiveInvitationConfig = ReceiveOutOfBandInvitationConfig(
        autoAcceptConnection: true)

    override func setUp() async throws {
        try await super.setUp()

        var faberConfig = try TestHelper.getBaseConfig(name: "faber", useLedgerService: true)
        var aliceConfig = try TestHelper.getBaseConfig(name: "alice", useLedgerService: true)
        faberConfig.autoAcceptCredential = .always
        faberConfig.autoAcceptProof = .always
        aliceConfig.autoAcceptCredential = .always
        aliceConfig.autoAcceptProof = .always

        self.faberAgent = Agent(agentConfig: faberConfig, agentDelegate: nil)
        self.aliceAgent = Agent(agentConfig: aliceConfig, agentDelegate: nil)

        self.faberAgent.setOutboundTransport(SubjectOutboundTransport(subject: aliceAgent))
        self.aliceAgent.setOutboundTransport(SubjectOutboundTransport(subject: faberAgent))

        try await faberAgent.initialize()
        try await aliceAgent.initialize()

        credDefId = try await TestHelper.prepareForIssuance(faberAgent, ["name", "age"])
    }

    override func tearDown() async throws {
        try await faberAgent?.reset()
        try await aliceAgent?.reset()
        try await super.tearDown()
    }

    func validateCredentialExchangeRecordState(for agent: Agent, threadId: String, state: CredentialState) async throws {
        let record = try await agent.credentialExchangeRepository.getByThreadAndConnectionId(threadId: threadId, connectionId: nil)
        XCTAssertEqual(record.state, state, "agent=\(agent.agentConfig.label)")
    }

    func testConnectionlessIssuance() async throws {
        let offerOptions = CreateOfferOptions(
            connection: faberConnection,
            credentialDefinitionId: credDefId,
            attributes: credentialPreview.attributes,
            comment: "Offer to Alice in connection-less way")
        let (message, record) = try await faberAgent.credentialService.createOffer(options: offerOptions)
        try await validateCredentialExchangeRecordState(for: faberAgent, threadId: record.threadId, state: .OfferSent)

        let oobConfig = CreateOutOfBandInvitationConfig(
            label: "FaberCollage",
            alias: "FaberCollage",
            imageUrl: nil,
            goalCode: nil,
            goal: nil,
            handshake: false,
            messages: [message],
            multiUseInvitation: false,
            autoAcceptConnection: true,
            routing: nil)
        let oobInvitation = try await faberAgent.oob.createInvitation(config: oobConfig)

        var (oob, connection) = try await aliceAgent.oob.receiveInvitation(oobInvitation.outOfBandInvitation)
        XCTAssertNotNil(connection)
        XCTAssertEqual(connection?.state, .Complete) // this is a fake connection.
        XCTAssertNotNil(oob)

        (oob, connection) = try await aliceAgent.oob.acceptInvitation(outOfBandId: oob.id, config: receiveInvitationConfig)
        XCTAssertNotNil(connection)
        XCTAssertNotNil(oob)
        try await validateCredentialExchangeRecordState(for: aliceAgent, threadId: record.threadId, state: .RequestSent)

        try await Task.sleep(nanoseconds: UInt64(5 * SECOND))

        try await validateCredentialExchangeRecordState(for: aliceAgent, threadId: record.threadId, state: .Done)
        try await validateCredentialExchangeRecordState(for: faberAgent, threadId: record.threadId, state: .Done)
    }
}
