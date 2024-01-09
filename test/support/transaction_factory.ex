defmodule Archethic.TransactionFactory do
  @moduledoc false

  alias Archethic.Crypto

  alias Archethic.Election

  alias Archethic.Mining.Fee

  alias Archethic.TransactionChain
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.CrossValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.TransactionMovement

  alias Archethic.TransactionChain.TransactionData
  alias Archethic.TransactionChain.TransactionData.Ledger

  alias Archethic.SharedSecrets

  import ArchethicCase

  def create_non_valided_transaction(opts \\ []) do
    type = Keyword.get(opts, :type, :transfer)
    seed = Keyword.get(opts, :seed, "seed")
    index = Keyword.get(opts, :index, 0)
    content = Keyword.get(opts, :content, "")
    code = Keyword.get(opts, :code, "")
    ledger = Keyword.get(opts, :ledger, %Ledger{})
    recipients = Keyword.get(opts, :recipients, [])
    ownerships = Keyword.get(opts, :ownerships, [])

    Transaction.new(
      type,
      %TransactionData{
        content: content,
        code: code,
        ledger: ledger,
        recipients: recipients,
        ownerships: ownerships
      },
      seed,
      index
    )
  end

  def create_valid_transaction(
        inputs \\ [
          %UnspentOutput{
            type: :UCO,
            amount: 1_000_000_000,
            from: random_address(),
            timestamp: DateTime.utc_now()
          }
        ],
        opts \\ []
      ) do
    type = Keyword.get(opts, :type, :transfer)
    seed = Keyword.get(opts, :seed, "seed")
    index = Keyword.get(opts, :index, 0)
    content = Keyword.get(opts, :content, "")
    code = Keyword.get(opts, :code, "")
    ledger = Keyword.get(opts, :ledger, %Ledger{})
    ownerships = Keyword.get(opts, :ownerships, [])
    recipients = Keyword.get(opts, :recipients, [])
    encoded_state = Keyword.get(opts, :state)
    prev_tx = Keyword.get(opts, :prev_tx)

    timestamp =
      Keyword.get(opts, :timestamp, DateTime.utc_now()) |> DateTime.truncate(:millisecond)

    tx =
      Transaction.new(
        type,
        %TransactionData{
          content: content,
          code: code,
          ledger: ledger,
          ownerships: ownerships,
          recipients: recipients
        },
        seed,
        index
      )

    fee = Fee.calculate(tx, nil, 0.07, timestamp, encoded_state, 0, current_protocol_version())
    movements = Transaction.get_movements(tx)

    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        inputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp),
        encoded_state,
        timestamp
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, type)

    poi =
      case prev_tx do
        nil ->
          TransactionChain.proof_of_integrity([tx])

        _ ->
          TransactionChain.proof_of_integrity([tx, prev_tx])
      end

    validation_stamp =
      %ValidationStamp{
        timestamp: timestamp,
        proof_of_work: Crypto.origin_node_public_key(),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        proof_of_integrity: poi,
        ledger_operations: ledger_operations,
        protocol_version: ArchethicCase.current_protocol_version(),
        recipients: Enum.map(recipients, & &1.address)
      }
      |> ValidationStamp.sign()

    cross_validation_stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)
    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_not_atomic_commitment(unspent_outputs \\ []) do
    tx = create_valid_transaction(unspent_outputs)

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{inconsistencies: [:proof_of_work]},
        tx.validation_stamp
      )

    Map.update!(tx, :cross_validation_stamps, &[cross_validation_stamp | &1])
  end

  def create_valid_transaction_with_inconsistencies(inputs \\ []) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())
    movements = Transaction.get_movements(tx)

    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        inputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp),
        nil,
        timestamp
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    validation_stamp =
      %ValidationStamp{
        timestamp: timestamp,
        proof_of_work: Crypto.origin_node_public_key(),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        ledger_operations: ledger_operations,
        protocol_version: ArchethicCase.current_protocol_version()
      }
      |> ValidationStamp.sign()

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{inconsistencies: [:signature]},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_proof_of_work(inputs \\ []) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)

    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())
    movements = Transaction.get_movements(tx)

    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        inputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp),
        nil,
        timestamp
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    validation_stamp = %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: <<0, 0, :crypto.strong_rand_bytes(32)::binary>>,
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      signature: :crypto.strong_rand_bytes(32),
      protocol_version: ArchethicCase.current_protocol_version()
    }

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_validation_stamp_signature(inputs \\ [], opts \\ []) do
    type = Keyword.get(opts, :type, :transfer)
    seed = Keyword.get(opts, :seed, "seed")
    index = Keyword.get(opts, :index, 0)

    timestamp =
      Keyword.get(opts, :timestamp, DateTime.utc_now()) |> DateTime.truncate(:millisecond)

    tx = Transaction.new(type, %TransactionData{}, seed, index)

    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())
    movements = Transaction.get_movements(tx)

    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        inputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp),
        nil,
        timestamp
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, type)

    validation_stamp = %ValidationStamp{
      timestamp: timestamp,
      proof_of_work: Crypto.origin_node_public_key(),
      proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
      proof_of_election: Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
      ledger_operations: ledger_operations,
      signature: :crypto.strong_rand_bytes(32),
      protocol_version: ArchethicCase.current_protocol_version()
    }

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_fee(inputs \\ []) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    movements = Transaction.get_movements(tx)

    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: 1_000_000_000}
      |> LedgerOperations.consume_inputs(
        tx.address,
        inputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp),
        nil,
        timestamp
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    validation_stamp =
      %ValidationStamp{
        timestamp: timestamp,
        proof_of_work: Crypto.origin_node_public_key(),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        ledger_operations: ledger_operations,
        protocol_version: ArchethicCase.current_protocol_version()
      }
      |> ValidationStamp.sign()

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  def create_transaction_with_invalid_transaction_movements(inputs \\ []) do
    tx = Transaction.new(:transfer, %TransactionData{}, "seed", 0)
    timestamp = DateTime.utc_now() |> DateTime.truncate(:millisecond)

    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())
    movements = [%TransactionMovement{to: "@Bob4", amount: 30_330_000_000, type: :UCO}]

    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        inputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp),
        nil,
        timestamp
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    validation_stamp =
      %ValidationStamp{
        timestamp: timestamp,
        proof_of_work: Crypto.origin_node_public_key(),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx]),
        proof_of_election:
          Election.validation_nodes_election_seed_sorting(tx, DateTime.utc_now()),
        ledger_operations: ledger_operations,
        protocol_version: ArchethicCase.current_protocol_version()
      }
      |> ValidationStamp.sign()

    cross_validation_stamp =
      CrossValidationStamp.sign(
        %CrossValidationStamp{},
        validation_stamp
      )

    %{tx | validation_stamp: validation_stamp, cross_validation_stamps: [cross_validation_stamp]}
  end

  @doc """
  Creates a valid Node Shared Secrets Tx with parameters index, timestamp, prev_txn
  """
  @spec create_network_tx(:node_shared_secrets, keyword) ::
          Archethic.TransactionChain.Transaction.t()
  def create_network_tx(_type = :node_shared_secrets, opts) do
    inputs = Keyword.get(opts, :inputs, [])
    seed = Keyword.get(opts, :seed, "daily_nonce_seed")
    index = Keyword.get(opts, :index)
    timestamp = Keyword.get(opts, :timestamp)
    aes_key = :crypto.strong_rand_bytes(32)
    prev_txn = Keyword.get(opts, :prev_txn, [])

    tx =
      SharedSecrets.new_node_shared_secrets_transaction(
        [Crypto.last_node_public_key()],
        seed,
        aes_key,
        index
      )

    fee = Fee.calculate(tx, nil, 0.07, timestamp, nil, 0, current_protocol_version())
    movements = Transaction.get_movements(tx)

    resolved_addresses = Enum.map(movements, &{&1.to, &1.to}) |> Map.new()

    ledger_operations =
      %LedgerOperations{fee: fee}
      |> LedgerOperations.consume_inputs(
        tx.address,
        inputs,
        movements,
        LedgerOperations.get_utxos_from_transaction(tx, timestamp),
        nil,
        timestamp
      )
      |> elem(1)
      |> LedgerOperations.build_resolved_movements(movements, resolved_addresses, tx.type)

    validation_stamp =
      %ValidationStamp{
        timestamp: timestamp,
        proof_of_work: Crypto.origin_node_public_key(),
        proof_of_election: Election.validation_nodes_election_seed_sorting(tx, timestamp),
        proof_of_integrity: TransactionChain.proof_of_integrity([tx | prev_txn]),
        ledger_operations: ledger_operations,
        protocol_version: ArchethicCase.current_protocol_version()
      }
      |> ValidationStamp.sign()

    cross_validation_stamp = CrossValidationStamp.sign(%CrossValidationStamp{}, validation_stamp)

    %{
      tx
      | validation_stamp: validation_stamp,
        cross_validation_stamps: [cross_validation_stamp]
    }
  end
end
