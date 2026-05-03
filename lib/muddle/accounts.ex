defmodule Muddle.Accounts do
  @moduledoc """
  The Accounts context.

  Owns registered users (email + magic-link/password), anonymous guests
  (created when someone joins a video call by share link without an
  account), session tokens, and the single-use invite system.
  """

  import Ecto.Query, warn: false
  alias Muddle.Repo

  alias Muddle.Accounts.{User, UserToken, UserNotifier}

  ## Database getters

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Registers an anonymous user. Used by the guest-link redemption flow
  for visitors who join a video call without an account.
  """
  def register_anonymous_user(attrs \\ %{}) do
    %User{}
    |> User.anonymous_changeset(attrs)
    |> Repo.insert()
  end

  ## Invites ----------------------------------------------------------------

  alias Muddle.Accounts.Invite

  @spec registration_open?() :: boolean()
  def registration_open? do
    Application.get_env(:muddle, :registration_open, false) == true
  end

  def create_invite(%User{id: id}, attrs \\ %{}) do
    %Invite{created_by_id: id}
    |> Invite.create_changeset(attrs)
    |> Repo.insert()
  end

  def list_invites(%User{id: id}) do
    from(i in Invite,
      where: i.created_by_id == ^id,
      order_by: [desc: i.inserted_at],
      preload: [:consumed_by]
    )
    |> Repo.all()
  end

  @spec get_active_invite(binary()) :: Invite.t() | nil
  def get_active_invite(token) when is_binary(token) do
    case Repo.get_by(Invite, token: token) do
      nil -> nil
      invite -> if Invite.active?(invite), do: invite, else: nil
    end
  end

  def get_active_invite(_), do: nil

  def consume_invite(%Invite{} = invite, %User{} = user) do
    invite
    |> Invite.consume_changeset(user)
    |> Repo.update()
  end

  def revoke_invite(%User{id: owner_id}, %Invite{created_by_id: owner_id} = invite) do
    invite
    |> Ecto.Changeset.change(
      consumed_at: DateTime.utc_now() |> DateTime.truncate(:second),
      consumed_by_id: nil
    )
    |> Repo.update()
  end

  def revoke_invite(_, _), do: {:error, :forbidden}

  ## Settings

  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
