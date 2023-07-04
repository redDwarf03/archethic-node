defmodule Archethic.Contracts.Interpreter.Library.Common.Token do
  @moduledoc false
  @behaviour Archethic.Contracts.Interpreter.Library

  alias Archethic.Contracts.Interpreter.ASTHelper, as: AST
  alias Archethic.Contracts.Interpreter.Library.Common.TokenImpl

  use Knigge, otp_app: :archethic, default: TokenImpl, delegate_at_runtime?: true

  @callback fetch_id_from_address(binary()) :: binary()

  @spec check_types(atom(), list()) :: boolean()
  def check_types(:fetch_id_from_address, [first]) do
    AST.is_binary?(first) || AST.is_variable_or_function_call?(first)
  end

  def check_types(_, _), do: false
end
