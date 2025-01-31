
import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v0.14.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Ensure that energy assets can be registered and listed for sale",
    async fn(chain: Chain, accounts: Map<string, Account>)
    {
        const deployer = accounts.get("deployer")!;
        const producer = accounts.get("wallet_1")!;
        const verifier = accounts.get("wallet_2")!;

        let block = chain.mineBlock([
            // Register energy asset
            Tx.contractCall(
                "sustainable_energy_market",
                "register-energy-asset",
                [
                    types.utf8("solar"),
                    types.uint(1000),
                    types.utf8("New York, USA"),
                    types.uint(52560)
                ],
                producer.address
            ),
            // Verify the asset
            Tx.contractCall(
                "sustainable_energy_market",
                "verify-energy-asset",
                [
                    types.uint(1),
                    types.utf8("GREEN-CERT-001")
                ],
                verifier.address
            ),
            // Create market listing
            Tx.contractCall(
                "sustainable_energy_market",
                "create-market-listing",
                [
                    types.uint(1),
                    types.uint(100),
                    types.uint(100)
                ],
                producer.address
            )
        ]);

        // Assert successful asset registration
        assertEquals(block.receipts[0].result, '(ok u1)');
        // Assert successful verification
        assertEquals(block.receipts[1].result, '(ok true)');
        // Assert successful listing creation
        assertEquals(block.receipts[2].result, '(ok u1)');
        assertEquals(block.height, 2);
    },
});

Clarinet.test({
    name: "Ensure that energy credits can be purchased and balances are updated correctly",
    async fn(chain: Chain, accounts: Map<string, Account>)
    {
        const producer = accounts.get("wallet_1")!;
        const verifier = accounts.get("wallet_2")!;
        const consumer = accounts.get("wallet_3")!;

        let block = chain.mineBlock([
            // Setup: Register and verify asset
            Tx.contractCall(
                "sustainable_energy_market",
                "register-energy-asset",
                [
                    types.utf8("solar"),
                    types.uint(1000),
                    types.utf8("New York, USA"),
                    types.uint(52560)
                ],
                producer.address
            ),
            Tx.contractCall(
                "sustainable_energy_market",
                "verify-energy-asset",
                [
                    types.uint(1),
                    types.utf8("GREEN-CERT-001")
                ],
                verifier.address
            ),
            // Create listing
            Tx.contractCall(
                "sustainable_energy_market",
                "create-market-listing",
                [
                    types.uint(1),
                    types.uint(100),
                    types.uint(100)
                ],
                producer.address
            )
        ]);

        block = chain.mineBlock([
            // Purchase energy credits
            Tx.contractCall(
                "sustainable_energy_market",
                "purchase-energy-credits",
                [
                    types.uint(1),
                    types.uint(200)
                ],
                consumer.address
            )
        ]);

        // Assert successful purchase
        assertEquals(block.receipts[0].result, '(ok true)');
        assertEquals(block.height, 3);
    },
});

Clarinet.test({
    name: "Ensure that unauthorized users cannot verify energy assets",
    async fn(chain: Chain, accounts: Map<string, Account>)
    {
        const producer = accounts.get("wallet_1")!;
        const unauthorized = accounts.get("wallet_3")!;

        let block = chain.mineBlock([
            // Register asset
            Tx.contractCall(
                "sustainable_energy_market",
                "register-energy-asset",
                [
                    types.utf8("solar"),
                    types.uint(1000),
                    types.utf8("New York, USA"),
                    types.uint(52560)
                ],
                producer.address
            )
        ]);

        block = chain.mineBlock([
            // Attempt unauthorized verification
            Tx.contractCall(
                "sustainable_energy_market",
                "verify-energy-asset",
                [
                    types.uint(1),
                    types.utf8("GREEN-CERT-001")
                ],
                unauthorized.address
            )
        ]);

        assertEquals(block.receipts[0].result, `(err u1)`); // ERR-NOT-AUTHORIZED
        assertEquals(block.height, 3);
    },
});

Clarinet.test({
    name: "Ensure that platform parameters can only be updated by contract owner",
    async fn(chain: Chain, accounts: Map<string, Account>)
    {
        const deployer = accounts.get("deployer")!;
        const unauthorized = accounts.get("wallet_1")!;

        let block = chain.mineBlock([
            // Attempt unauthorized fee update
            Tx.contractCall(
                "sustainable_energy_market",
                "update-platform-fee",
                [types.uint(30)],
                unauthorized.address
            ),
            // Authorized fee update
            Tx.contractCall(
                "sustainable_energy_market",
                "update-platform-fee",
                [types.uint(30)],
                deployer.address
            )
        ]);

        assertEquals(block.receipts[0].result, `(err u1)`); // ERR-NOT-AUTHORIZED
        assertEquals(block.receipts[1].result, '(ok true)');
        assertEquals(block.height, 2);
    },
});

Clarinet.test({
    name: "Ensure that expired listings cannot be purchased",
    async fn(chain: Chain, accounts: Map<string, Account>)
    {
        const producer = accounts.get("wallet_1")!;
        const verifier = accounts.get("wallet_2")!;
        const consumer = accounts.get("wallet_3")!;

        let block = chain.mineBlock([
            // Setup: Register asset with short expiry
            Tx.contractCall(
                "sustainable_energy_market",
                "register-energy-asset",
                [
                    types.utf8("solar"),
                    types.uint(1000),
                    types.utf8("New York, USA"),
                    types.uint(1) // Very short expiry
                ],
                producer.address
            ),
            // Verify asset
            Tx.contractCall(
                "sustainable_energy_market",
                "verify-energy-asset",
                [
                    types.uint(1),
                    types.utf8("GREEN-CERT-001")
                ],
                verifier.address
            ),
            // Create listing
            Tx.contractCall(
                "sustainable_energy_market",
                "create-market-listing",
                [
                    types.uint(1),
                    types.uint(100),
                    types.uint(100)
                ],
                producer.address
            )
        ]);

        // Mine a few blocks to ensure expiry
        chain.mineEmptyBlock(10);

        block = chain.mineBlock([
            // Attempt to purchase expired listing
            Tx.contractCall(
                "sustainable_energy_market",
                "purchase-energy-credits",
                [
                    types.uint(1),
                    types.uint(200)
                ],
                consumer.address
            )
        ]);

        assertEquals(block.receipts[0].result, `(err u9)`); // ERR-EXPIRED
    },
});

Clarinet.test({
    name: "Ensure that minimum purchase amounts are enforced",
    async fn(chain: Chain, accounts: Map<string, Account>)
    {
        const producer = accounts.get("wallet_1")!;
        const verifier = accounts.get("wallet_2")!;
        const consumer = accounts.get("wallet_3")!;

        let block = chain.mineBlock([
            // Setup: Register and verify asset
            Tx.contractCall(
                "sustainable_energy_market",
                "register-energy-asset",
                [
                    types.utf8("solar"),
                    types.uint(1000),
                    types.utf8("New York, USA"),
                    types.uint(52560)
                ],
                producer.address
            ),
            Tx.contractCall(
                "sustainable_energy_market",
                "verify-energy-asset",
                [
                    types.uint(1),
                    types.utf8("GREEN-CERT-001")
                ],
                verifier.address
            ),
            // Create listing with minimum purchase of 100
            Tx.contractCall(
                "sustainable_energy_market",
                "create-market-listing",
                [
                    types.uint(1),
                    types.uint(100),
                    types.uint(100)
                ],
                producer.address
            )
        ]);

        block = chain.mineBlock([
            // Attempt to purchase below minimum amount
            Tx.contractCall(
                "sustainable_energy_market",
                "purchase-energy-credits",
                [
                    types.uint(1),
                    types.uint(50)
                ],
                consumer.address
            )
        ]);

        assertEquals(block.receipts[0].result, `(err u2)`); // ERR-INVALID-AMOUNT
    },
});
