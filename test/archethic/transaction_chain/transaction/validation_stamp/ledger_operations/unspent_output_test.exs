defmodule Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutputTest do
  use ArchethicCase

  import ArchethicCase, only: [current_protocol_version: 0]
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput
  doctest UnspentOutput
end
