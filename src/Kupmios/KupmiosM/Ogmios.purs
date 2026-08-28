module Cardano.Kupmios.Ogmios
  ( currentEpoch
  , delegationsAndRewards
  , eraSummaries
  , evaluateTxOgmios
  , getChainTip
  , getProposalById
  , getProtocolParameters
  , getRegisteredDrepInfo
  , getSystemStartTime
  , getVotesOnProposal
  , ogmiosQueryNoParams
  , ogmiosQueryParams
  , poolParameters
  , submitTxOgmios
  ) where

import Prelude

import Aeson
  ( class DecodeAeson
  , class EncodeAeson
  , Aeson
  , JsonDecodeError(TypeMismatch)
  , caseAesonArray
  , caseAesonObject
  , decodeAeson
  , encodeAeson
  , getField
  , parseJsonStringToAeson
  , stringifyAeson
  )
import Aeson as Aeson
import Affjax (Error, Response, defaultRequest) as Affjax
import Affjax (printError)
import Affjax.RequestBody as Affjax.RequestBody
import Affjax.RequestHeader as Affjax.RequestHeader
import Affjax.ResponseFormat (string) as Affjax.ResponseFormat
import Affjax.StatusCode (StatusCode(StatusCode))
import Cardano.AsCbor (decodeCbor, encodeCbor)
import Cardano.Kupmios.KupmiosM (KupmiosM)
import Cardano.Kupmios.KupmiosM.HttpUtils (handleAffjaxResponseGeneric)
import Cardano.Kupmios.Logging (logTrace')
import Cardano.Kupmios.Ogmios.Types
  ( class DecodeOgmios
  , AdditionalUtxoSet
  , ChainTipQR(CtChainPoint, CtChainOrigin)
  , CurrentEpoch
  , DelegationsAndRewardsR
  , OgmiosAdaLovelace
  , OgmiosDecodeError(ErrorResponse, InvalidRpcResponse)
  , OgmiosEraSummaries
  , OgmiosError(OgmiosError)
  , OgmiosProtocolParameters
  , OgmiosSystemStart
  , PoolParametersR
  , StakePoolsQueryArgument
  , SubmitTxR
  , decodeOgmios
  , decodeResult
  , pprintOgmiosDecodeError
  )
import Cardano.Provider
  ( Proposal
  , ProposalType
      ( TriggerHardFork
      , NewCommittee
      , NewConstitution
      , Info
      , NoConfidence
      , ChangeProtocolParameters
      , TreasuryWithdrawal
      )
  , VoteOnProposal
  , DrepInfo
  )
import Cardano.Provider.Affjax (request) as Affjax
import Cardano.Provider.OgmiosTypes (TxEvaluationR)
import Cardano.Provider.ServerConfig (ServerConfig, mkHttpUrl)
import Cardano.Types
  ( Coin(Coin)
  , Credential(PubKeyHashCredential, ScriptHashCredential)
  , GovernanceActionId(GovernanceActionId)
  , Vote(VoteNo, VoteYes, VoteAbstain)
  , Voter(Cc, Drep, Spo)
  )
import Cardano.Types.CborBytes (CborBytes)
import Cardano.Types.Chain as Chain
import Cardano.Types.Ed25519KeyHash (fromBech32) as Ed25519KeyHash
import Cardano.Types.RewardAddress (fromBech32) as RewardAddress
import Cardano.Types.TransactionHash (TransactionHash)
import Concurrent.BoundedQueue (BoundedQueue)
import Concurrent.BoundedQueue (isEmpty, read, write) as BoundedQueue
import Control.Monad.Error.Class (class MonadThrow, throwError)
import Control.Monad.Reader.Class (ask)
import Data.Array (catMaybes, length, singleton) as Array
import Data.ByteArray (byteArrayToHex, hexToByteArray)
import Data.Either (Either(Left), either, note)
import Data.HTTP.Method (Method(POST))
import Data.Lens (_Right, to, (^?))
import Data.Maybe (Maybe(Just, Nothing), maybe)
import Data.Newtype (class Newtype, unwrap, wrap)
import Data.Time.Duration (Milliseconds(Milliseconds))
import Data.Traversable (traverse)
import Data.Tuple.Nested (type (/\), (/\))
import Data.UInt (toInt) as UInt
import Effect.Aff (Aff, bracket, delay)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Exception (Error, error)
import Foreign.Object (Object)

--------------------------------------------------------------------------------
-- Local State Query Protocol
-- https://ogmios.dev/mini-protocols/local-state-query/
--------------------------------------------------------------------------------

-- TODO: move to Cardano.Kupmios.Ogmios.Types
newtype ProposalReferenceArgument = ProposalReferenceArgument GovernanceActionId

derive instance Newtype ProposalReferenceArgument _

instance EncodeAeson ProposalReferenceArgument where
  encodeAeson (ProposalReferenceArgument (GovernanceActionId { transactionId, index })) =
    encodeAeson
      { proposals: Array.singleton
          { transaction:
              { id: byteArrayToHex $ unwrap $ encodeCbor transactionId
              }
          , index: UInt.toInt index
          }
      }

-- TODO: move to Cardano.Kupmios.Ogmios.Types
newtype OgmiosProposal = OgmiosProposal (Maybe Proposal)

derive instance Newtype OgmiosProposal _

instance DecodeOgmios OgmiosProposal where
  decodeOgmios = decodeResult decodeAeson

instance DecodeAeson OgmiosProposal where
  decodeAeson =
    caseAesonArray (Left $ TypeMismatch "Array")
      case _ of
        [] -> pure $ wrap Nothing
        [ proposalAeson ] ->
          caseAesonObject (Left $ TypeMismatch "Object")
            ( \obj -> do
                returnAddress <- do
                  returnAddressBech32 <- getField obj "returnAccount"
                  note (TypeMismatch "Expected Bech32-encoded reward address") $
                    RewardAddress.fromBech32 returnAddressBech32
                deposit <- do
                  (depositRaw :: OgmiosAdaLovelace) <- getField obj "deposit"
                  pure $ Coin depositRaw.ada.lovelace
                proposalType <- do
                  actionObj <- getField obj "action"
                  proposalTypeRaw <- getField actionObj "type"
                  note (TypeMismatch "Expected string corresponding to ProposalType constr") $
                    proposalTypeFromOgmiosString proposalTypeRaw
                pure $ wrap $ Just
                  { proposalType
                  , deposit
                  , returnAddress
                  }
            )
            proposalAeson
        xs ->
          Left $ TypeMismatch $ "Expected one proposal, got " <> show (Array.length xs)

unwrapOgmiosProposal :: OgmiosProposal -> Maybe Proposal
unwrapOgmiosProposal = unwrap

-- treasuryTransfer?
proposalTypeFromOgmiosString :: String -> Maybe ProposalType
proposalTypeFromOgmiosString =
  case _ of
    "hardForkInitiation" ->
      Just TriggerHardFork
    "constitutionalCommittee" ->
      Just NewCommittee
    "constitution" ->
      Just NewConstitution
    "information" ->
      Just Info
    "noConfidence" ->
      Just NoConfidence
    "protocolParametersUpdate" ->
      Just ChangeProtocolParameters
    "treasuryWithdrawals" ->
      Just TreasuryWithdrawal
    _ -> Nothing

getProposalById :: GovernanceActionId -> KupmiosM (Either OgmiosDecodeError (Maybe Proposal))
getProposalById proposalRef =
  map unwrapOgmiosProposal <$> ogmiosQueryParams "queryLedgerState/governanceProposals"
    (ProposalReferenceArgument proposalRef)

--

voteFromOgmiosString :: String -> Maybe Vote
voteFromOgmiosString =
  case _ of
    "no" -> Just VoteNo
    "yes" -> Just VoteYes
    "abstain" -> Just VoteAbstain
    _ -> Nothing

newtype OgmiosVotesOnProposal = OgmiosVotesOnProposal (Array VoteOnProposal)

derive instance Newtype OgmiosVotesOnProposal _

instance DecodeOgmios OgmiosVotesOnProposal where
  decodeOgmios = decodeResult decodeAeson

instance DecodeAeson OgmiosVotesOnProposal where
  decodeAeson =
    caseAesonArray (Left $ TypeMismatch "Array")
      case _ of
        [] -> pure $ wrap []
        [ proposalAeson ] ->
          caseAesonObject (Left $ TypeMismatch "Object")
            ( \obj -> do
                (voteObjects :: Array (Object Aeson)) <- getField obj "votes"
                votes <- traverse decodeOgmiosVote voteObjects
                pure $ wrap votes
            )
            proposalAeson
        xs ->
          Left $ TypeMismatch $ "Expected one proposal, got " <> show (Array.length xs)
    where
    decodeOgmiosVote :: Object Aeson -> Either JsonDecodeError VoteOnProposal
    decodeOgmiosVote obj = do
      voteRaw <- getField obj "vote"
      vote <- note (TypeMismatch "Expected string repr of Vote") $ voteFromOgmiosString voteRaw
      voterObj <- getField obj "issuer"
      voterRole <- getField voterObj "role"
      credType <- getField voterObj "from"
      credRaw <- getField voterObj "id"
      -- TODO: Should we handle genesisDelegate?
      voter <- case voterRole of
        "constitutionalCommittee" ->
          Cc <$> decodeCredential credType credRaw
        "delegateRepresentative" ->
          Drep <$> decodeCredential credType credRaw
        "stakePoolOperator" -> do
          pkh <- note (TypeMismatch "Expected Bech32-encoded stake pool pkh") $
            Ed25519KeyHash.fromBech32 credRaw
          pure $ Spo pkh
        _ ->
          Left $ TypeMismatch $ "Unexpected voter role: " <> voterRole
      pure { voter, vote }
      where
      decodeCredential :: String -> String -> Either JsonDecodeError Credential
      decodeCredential credType cred =
        case credType of
          "verificationKey" ->
            note (TypeMismatch "Expected Base16-encoded Ed25519KeyHash bytes")
              ( PubKeyHashCredential <$>
                  (decodeCbor <<< wrap =<< hexToByteArray cred)
              )
          "script" ->
            note (TypeMismatch "Expected Base16-encoded ScriptHash bytes")
              ( ScriptHashCredential <$>
                  (decodeCbor <<< wrap =<< hexToByteArray cred)
              )
          _ ->
            Left $ TypeMismatch $ "Unexpected credential type: "
              <> credType

unwrapOgmiosVotesOnProposal :: OgmiosVotesOnProposal -> Array VoteOnProposal
unwrapOgmiosVotesOnProposal = unwrap

getVotesOnProposal
  :: GovernanceActionId
  -> KupmiosM (Either OgmiosDecodeError (Array VoteOnProposal))
getVotesOnProposal proposalRef =
  map unwrapOgmiosVotesOnProposal <$> ogmiosQueryParams "queryLedgerState/governanceProposals"
    (ProposalReferenceArgument proposalRef)

--

newtype DrepCredentialArgument = DrepCredentialArgument Credential

derive instance Newtype DrepCredentialArgument _

instance EncodeAeson DrepCredentialArgument where
  encodeAeson (DrepCredentialArgument drepCred) =
    case drepCred of
      PubKeyHashCredential pkh ->
        encodeAeson
          { scripts: ([] :: Array String)
          , keys:
              [ byteArrayToHex $ unwrap $ encodeCbor pkh
              ]
          }
      ScriptHashCredential sh ->
        encodeAeson
          { scripts:
              [ byteArrayToHex $ unwrap $ encodeCbor sh
              ]
          , keys: ([] :: Array String)
          }

newtype OgmiosDrepInfo = OgmiosDrepInfo (Maybe DrepInfo)

derive instance Newtype OgmiosDrepInfo _

instance DecodeOgmios OgmiosDrepInfo where
  decodeOgmios = decodeResult decodeAeson

instance DecodeAeson OgmiosDrepInfo where
  decodeAeson =
    caseAesonArray (Left $ TypeMismatch "Array") $ \xs -> do
      dreps <- Array.catMaybes <$> traverse
        ( \drepAeson ->
            caseAesonObject (Left $ TypeMismatch "Object")
              ( \obj -> do
                  type_ <- getField obj "type"
                  if type_ == "registered" then do
                    deposit <- do
                      (depositRaw :: OgmiosAdaLovelace) <- getField obj "deposit"
                      pure $ Coin depositRaw.ada.lovelace
                    votingPower <- do
                      (stake :: OgmiosAdaLovelace) <- getField obj "stake"
                      pure $ Coin stake.ada.lovelace
                    pure $ Just $ wrap $ Just
                      { deposit
                      , votingPower
                      }
                  else
                    pure Nothing
              )
              drepAeson
        )
        xs
      case dreps of
        [] -> pure $ wrap Nothing
        [ drep ] -> pure drep
        _ ->
          Left $ TypeMismatch $ "Expected one DRep entry, got " <>
            show (Array.length dreps)

unwrapOgmiosDrepInfo :: OgmiosDrepInfo -> Maybe DrepInfo
unwrapOgmiosDrepInfo = unwrap

getRegisteredDrepInfo
  :: Credential
  -> KupmiosM (Either OgmiosDecodeError (Maybe DrepInfo))
getRegisteredDrepInfo drepCred =
  map unwrapOgmiosDrepInfo <$> ogmiosQueryParams "queryLedgerState/delegateRepresentatives"
    (DrepCredentialArgument drepCred)

--

eraSummaries :: KupmiosM (Either OgmiosDecodeError OgmiosEraSummaries)
eraSummaries = ogmiosQueryNoParams "queryLedgerState/eraSummaries"

getSystemStartTime :: KupmiosM (Either OgmiosDecodeError OgmiosSystemStart)
getSystemStartTime = ogmiosQueryNoParams "queryNetwork/startTime"

getProtocolParameters
  :: KupmiosM (Either OgmiosDecodeError OgmiosProtocolParameters)
getProtocolParameters = ogmiosQueryNoParams
  "queryLedgerState/protocolParameters"

getChainTip :: KupmiosM Chain.Tip
getChainTip = do
  ogmiosChainTipToTip <$> ogmiosErrorHandler
    (ogmiosQueryNoParams "queryNetwork/tip")
  where
  ogmiosChainTipToTip :: ChainTipQR -> Chain.Tip
  ogmiosChainTipToTip = case _ of
    CtChainOrigin _ -> Chain.TipAtGenesis
    CtChainPoint { slot, id } -> Chain.Tip $ wrap
      { slot, blockHeaderHash: wrap $ unwrap id }

currentEpoch :: KupmiosM (Either OgmiosDecodeError CurrentEpoch)
currentEpoch = ogmiosQueryNoParams "queryLedgerState/epoch"

submitTxOgmios :: TransactionHash -> CborBytes -> KupmiosM SubmitTxR
submitTxOgmios txHash tx = ogmiosErrorHandlerWithArg submitTx
  (txHash /\ tx)
  where
  submitTx (_ /\ cbor) = ogmiosQueryParams "submitTransaction"
    { transaction:
        { cbor: byteArrayToHex (unwrap cbor)
        }
    }

poolParameters
  :: StakePoolsQueryArgument
  -> KupmiosM (Either OgmiosDecodeError PoolParametersR)
poolParameters stakePools = ogmiosQueryParams "queryLedgerState/stakePools"
  stakePools

delegationsAndRewards
  :: Array String -- ^ A list of reward account bech32 strings
  -> KupmiosM (Either OgmiosDecodeError DelegationsAndRewardsR)
delegationsAndRewards rewardAccounts = ogmiosQueryParams
  "queryLedgerState/rewardAccountSummaries"
  { query:
      { delegationsAndRewards: rewardAccounts }
  }

evaluateTxOgmios :: CborBytes -> AdditionalUtxoSet -> KupmiosM TxEvaluationR
evaluateTxOgmios cbor additionalUtxos = ogmiosErrorHandlerWithArg
  evaluateTx
  (cbor /\ additionalUtxos)
  where
  evaluateTx
    :: CborBytes /\ AdditionalUtxoSet
    -> KupmiosM (Either OgmiosDecodeError TxEvaluationR)
  evaluateTx (cbor_ /\ utxoqr) = ogmiosQueryParams "evaluateTransaction"
    { transaction: { cbor: byteArrayToHex $ unwrap cbor_ }
    , additionalUtxo: utxoqr
    }

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

ogmiosQueryNoParams
  :: forall a
   . DecodeOgmios a
  => String
  -> KupmiosM (Either OgmiosDecodeError a)
ogmiosQueryNoParams = flip ogmiosQueryParams {}

ogmiosQueryParams
  :: forall a p
   . DecodeOgmios a
  => EncodeAeson p
  => String
  -> p
  -> KupmiosM (Either OgmiosDecodeError a)
ogmiosQueryParams method params = do
  let
    body = Aeson.encodeAeson
      { jsonrpc: "2.0"
      , method
      , params
      }
  handleAffjaxOgmiosResponse <$> ogmiosPostRequest body

ogmiosPostRequest
  :: Aeson -- ^ JSON-RPC request body
  -> KupmiosM (Either Affjax.Error (Affjax.Response String))
ogmiosPostRequest body = do
  { config: { ogmios }, ogmiosRequestRateLimiter } <- ask
  logTrace' $ "sending ogmios HTTP request: " <> show body
  let request = ogmiosPostRequestAff ogmios.serverConfig body
  resp <-
    liftAff $ maybe request (\sem -> rateLimited sem ogmios.requestRateLimiterCooldown request)
      ogmiosRequestRateLimiter
  logTrace' $ "response: " <> either (show <<< printError) show resp
  pure resp

rateLimited :: forall (a :: Type). BoundedQueue Unit -> Maybe Milliseconds -> Aff a -> Aff a
rateLimited sem cooldown =
  bracket acquireSem (const (BoundedQueue.write sem unit))
    <<< const
  where
  acquireSem :: Aff Unit
  acquireSem =
    case cooldown of
      Nothing ->
        BoundedQueue.read sem
      Just cd ->
        BoundedQueue.isEmpty sem >>=
          case _ of
            false ->
              BoundedQueue.read sem
            true ->
              delay cd *> BoundedQueue.read sem

ogmiosPostRequestAff
  :: ServerConfig
  -> Aeson
  -> Aff (Either Affjax.Error (Affjax.Response String))
ogmiosPostRequestAff = ogmiosPostRequestRetryAff (Milliseconds 1000.0)

ogmiosPostRequestRetryAff
  :: Milliseconds
  -> ServerConfig
  -> Aeson
  -> Aff (Either Affjax.Error (Affjax.Response String))
ogmiosPostRequestRetryAff delayMs config body = do
  let
    req = Affjax.defaultRequest
      { method = Left POST
      , url = mkHttpUrl config
      , headers =
          [ Affjax.RequestHeader.RequestHeader "Content-Type"
              "application/json"
          ]
      , content = Just $ Affjax.RequestBody.String $ stringifyAeson body
      , responseFormat = Affjax.ResponseFormat.string
      }

  result <- Affjax.request req

  if result ^? _Right <<< to _.status == Just (StatusCode 503) then
    delay delayMs *>
      ogmiosPostRequestRetryAff (Milliseconds (unwrap delayMs * 2.0)) config
        body

  else pure result

handleAffjaxOgmiosResponse
  :: forall (result :: Type)
   . DecodeOgmios result
  => Either Affjax.Error (Affjax.Response String)
  -> Either OgmiosDecodeError result
handleAffjaxOgmiosResponse =
  handleAffjaxResponseGeneric
    { httpError:
        ( \err -> ErrorResponse $ Just $ OgmiosError
            { code: 0, message: printError err, data: Nothing }
        )
    , httpStatusCodeError:
        ( \code body -> ErrorResponse $ Just $ OgmiosError
            { code, message: "body: " <> body, data: Nothing }
        )
    , decodeError: (\_body jsonErr -> InvalidRpcResponse jsonErr)
    , parse: parseJsonStringToAeson
    , transform: decodeOgmios
    }

ogmiosErrorHandler
  :: forall a m
   . MonadAff m
  => MonadThrow Error m
  => m (Either OgmiosDecodeError a)
  -> m a
ogmiosErrorHandler fun = fun >>= either
  (throwError <<< error <<< pprintOgmiosDecodeError)
  pure

ogmiosErrorHandlerWithArg
  :: forall a m b
   . MonadAff m
  => MonadThrow Error m
  => (a -> m (Either OgmiosDecodeError b))
  -> a
  -> m b
ogmiosErrorHandlerWithArg fun arg = fun arg >>= either
  (throwError <<< error <<< pprintOgmiosDecodeError)
  pure
