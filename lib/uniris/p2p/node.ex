defmodule Uniris.P2P.Node do
  @moduledoc """
  Describe an Uniris P2P node

  Assumptions:
  - Each node by default is not authorized and become when a node shared secrets transaction involve it.
  - Each node by default is not available until the end of the node bootstrap or the next beacon chain daily summary updates
  - Each node by default has an average availability of 1 and decrease after beacon chain daily summary updates
  - Each node by default has a network equal to the geo patch, and is updated after each beacon chain daily summary updates
  """

  require Logger

  alias Uniris.Crypto
  alias Uniris.P2P.Transport

  defstruct [
    :first_public_key,
    :last_public_key,
    :ip,
    :port,
    :geo_patch,
    :network_patch,
    :enrollment_date,
    available?: false,
    average_availability: 1.0,
    availability_history: <<1::1>>,
    authorized?: false,
    authorization_date: nil,
    # TODO: support other transport (i.e udp/sctp)
    transport: Application.get_env(:uniris, Transport, impl: :tcp) |> Keyword.fetch!(:impl)
  ]

  @type t() :: %__MODULE__{
          first_public_key: nil | Crypto.key(),
          last_public_key: Crypto.key(),
          ip: nil | :inet.ip_address(),
          port: nil | :inet.port_number(),
          geo_patch: nil | binary(),
          network_patch: nil | binary(),
          available?: boolean(),
          average_availability: float(),
          availability_history: bitstring(),
          authorized?: boolean(),
          enrollment_date: nil | DateTime.t(),
          authorization_date: nil | DateTime.t(),
          transport: Transport.supported()
        }

  @doc """
  Convert a tuple from NodeLedger to a Node instance
  """
  @spec cast(tuple()) :: __MODULE__.t()
  def cast(
        {first_public_key, last_public_key, ip, port, geo_patch, network_patch,
         average_availability, availability_history, enrollment_date, transport}
      ) do
    %__MODULE__{
      ip: ip,
      port: port,
      first_public_key: first_public_key,
      last_public_key: last_public_key,
      geo_patch: geo_patch,
      network_patch: network_patch,
      average_availability: average_availability,
      availability_history: availability_history,
      enrollment_date: enrollment_date,
      transport: transport
    }
  end

  @doc """
  Determine if the node is locally available based on its availability history.

  If the last exchange with node was succeed the node is considered as available

  ## Examples

      iex> Node.locally_available?(%Node{ availability_history: <<1::1, 0::1, 1::1, 1::1>>})
      true

      iex> Node.locally_available?(%Node{ availability_history: <<0::1, 1::1, 1::1, 1::1>>})
      false

  """
  @spec locally_available?(t()) :: boolean()
  def locally_available?(%__MODULE__{availability_history: <<1::1, _::bitstring>>}), do: true
  def locally_available?(%__MODULE__{availability_history: <<0::1, _::bitstring>>}), do: false

  @doc """
  Determine if the node is globally available
  """
  @spec globally_available?(__MODULE__.t()) :: boolean()
  def globally_available?(%__MODULE__{available?: true}), do: true
  def globally_available?(%__MODULE__{available?: _}), do: false

  @doc """
  Mark the node as authorized by including the authorization date

  ## Examples

      iex> Node.authorize(%Node{}, ~U[2020-09-10 07:50:58.466314Z])
      %Node{
        authorized?: true,
        authorization_date: ~U[2020-09-10 07:50:58.466314Z]
      }
  """
  @spec authorize(__MODULE__.t(), DateTime.t()) :: __MODULE__.t()
  def authorize(node = %__MODULE__{}, authorization_date = %DateTime{}) do
    %{node | authorized?: true, authorization_date: authorization_date}
  end

  @doc """
  Mark the node as non-authorized by including the authorization date

  ## Examples

      iex> Node.remove_authorization(%Node{authorized?: true, authorization_date: ~U[2020-09-10 07:50:58.466314Z]})
      %Node{
        authorized?: false,
        authorization_date: nil
      }
  """
  @spec remove_authorization(__MODULE__.t()) :: __MODULE__.t()
  def remove_authorization(node = %__MODULE__{}) do
    %{node | authorized?: false, authorization_date: nil}
  end

  @doc """
  Mark the node as globally available
  """
  @spec available(__MODULE__.t()) :: __MODULE__.t()
  def available(node = %__MODULE__{}) do
    %{node | available?: true}
  end

  @doc """
  Mark the node as globally unavailable
  """
  @spec unavailable(__MODULE__.t()) :: __MODULE__.t()
  def unavailable(node = %__MODULE__{}) do
    %{node | available?: false}
  end

  @doc """
  Get the numerical value of the network patch hexadecimal
  """
  @spec get_network_patch_num(__MODULE__.t()) :: non_neg_integer()
  def get_network_patch_num(%__MODULE__{network_patch: patch}) do
    patch
    |> String.to_charlist()
    |> List.to_integer(16)
  end

  @doc """
  Define the roll as enrolled with the first transaction time and initialize the network patch
  with the geographical patch

  ## Examples

      iex> Node.enroll(%Node{geo_patch: "AAA"}, ~U[2020-09-10 07:50:58.466314Z])
      %Node{
        enrollment_date: ~U[2020-09-10 07:50:58.466314Z],
        geo_patch: "AAA",
        network_patch: "AAA"
      }
  """
  @spec enroll(__MODULE__.t(), date :: DateTime.t()) :: __MODULE__.t()
  def enroll(node = %__MODULE__{geo_patch: geo_patch}, date = %DateTime{}) do
    %{node | enrollment_date: date, network_patch: geo_patch}
  end

  # defp new_average_availability(history) do
  #   list = for <<view::1 <- history>>, do: view

  #   list
  #   |> Enum.frequencies()
  #   |> Map.get(1)
  #   |> case do
  #     nil ->
  #       0.0

  #     available_times ->
  #       Float.floor(available_times / bit_size(history), 1)
  #   end
  # end

  @doc """
  Serialize a node into binary format

  ## Examples

      iex> Node.serialize(%Node{
      ...>   first_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...>     92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
      ...>   last_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...>     92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
      ...>   ip: {127, 0, 0, 1},
      ...>   port: 3000,
      ...>   geo_patch: "FA9",
      ...>   network_patch: "AVC",
      ...>   available?: true,
      ...>   average_availability: 0.8,
      ...>   enrollment_date: ~U[2020-06-26 08:36:11Z],
      ...>   authorization_date: ~U[2020-06-26 08:36:11Z],
      ...>   authorized?: true
      ...> })
      <<
      # IP address
      127, 0, 0, 1,
      # Port
      11, 184,
      # Geo patch
      "FA9",
      # Network patch
      "AVC",
      # Avg availability
      80,
      # Enrollment date
      94, 245, 179, 123,
      # Available
      1::1,
      # Authorized
      1::1,
      # Authorization date
      94, 245, 179, 123,
      # First public key
      0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226,
      # Last public key
      0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226
      >>
  """
  @spec serialize(__MODULE__.t()) :: bitstring()
  def serialize(%__MODULE__{
        ip: {o1, o2, o3, o4},
        port: port,
        first_public_key: first_public_key,
        last_public_key: last_public_key,
        geo_patch: geo_patch,
        network_patch: network_patch,
        average_availability: average_availability,
        enrollment_date: enrollment_date,
        available?: available?,
        authorized?: authorized?,
        authorization_date: authorization_date
      }) do
    ip_bin = <<o1, o2, o3, o4>>
    available_bin = if available?, do: 1, else: 0
    authorized_bin = if authorized?, do: 1, else: 0

    authorization_date =
      if authorization_date == nil, do: 0, else: DateTime.to_unix(authorization_date)

    avg_bin = trunc(average_availability * 100)

    <<ip_bin::binary-size(4), port::16, geo_patch::binary-size(3), network_patch::binary-size(3),
      avg_bin::8, DateTime.to_unix(enrollment_date)::32, available_bin::1, authorized_bin::1,
      authorization_date::32, first_public_key::binary, last_public_key::binary>>
  end

  @doc """
  Deserialize an encoded node

  ## Examples

      iex> Node.deserialize(<<
      ...> 127, 0, 0, 1, 11, 184, "FA9", "AVC", 80,
      ...> 94, 245, 179, 123, 1::1,
      ...> 1::1, 94, 245, 179, 123,
      ...> 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...> 92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226,
      ...> 0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
      ...> 92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226
      ...> >>)
      {
        %Node{
            first_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
              92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            last_public_key: <<0, 182, 67, 168, 252, 227, 203, 142, 164, 142, 248, 159, 209, 249, 247, 86, 64,
              92, 224, 91, 182, 122, 49, 209, 169, 96, 111, 219, 204, 57, 250, 59, 226>>,
            ip: {127, 0, 0, 1},
            port: 3000,
            geo_patch: "FA9",
            network_patch: "AVC",
            available?: true,
            average_availability: 0.8,
            enrollment_date: ~U[2020-06-26 08:36:11Z],
            authorization_date: ~U[2020-06-26 08:36:11Z],
            authorized?: true
        },
        ""
      }
  """
  @spec deserialize(bitstring()) :: {Uniris.P2P.Node.t(), bitstring}
  def deserialize(
        <<ip_bin::binary-size(4), port::16, geo_patch::binary-size(3),
          network_patch::binary-size(3), average_availability::8, enrollment_date::32,
          available::1, authorized::1, authorization_date::32, rest::bitstring>>
      ) do
    <<o1, o2, o3, o4>> = ip_bin
    available? = if available == 1, do: true, else: false
    authorized? = if authorized == 1, do: true, else: false

    authorization_date =
      if authorization_date == 0, do: nil, else: DateTime.from_unix!(authorization_date)

    <<first_curve_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(first_curve_id)
    <<first_key::binary-size(key_size), last_curve_id::8, rest::bitstring>> = rest
    key_size = Crypto.key_size(first_curve_id)
    <<last_key::binary-size(key_size), rest::bitstring>> = rest

    {
      %__MODULE__{
        ip: {o1, o2, o3, o4},
        port: port,
        geo_patch: geo_patch,
        network_patch: network_patch,
        average_availability: average_availability / 100,
        enrollment_date: DateTime.from_unix!(enrollment_date),
        available?: available?,
        authorized?: authorized?,
        authorization_date: authorization_date,
        first_public_key: <<first_curve_id::8>> <> first_key,
        last_public_key: <<last_curve_id::8>> <> last_key
      },
      rest
    }
  end
end
