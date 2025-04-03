-- | Kupo+Ogmios query layer monad.
-- | This module defines an Aff interface for backend queries.
module Cardano.Kupmios.KupmiosM
  ( KupmiosM
  , KupmiosEnv
  , KupmiosConfig
  , ParKupmiosM
  , KupmiosMT(KupmiosMT)
  , handleAffjaxResponse
  ) where

import Prelude

import Aeson (class DecodeAeson, decodeAeson, parseJsonStringToAeson)
import Affjax (Error, Response) as Affjax
import Cardano.Provider.Error
  ( ClientError(ClientHttpError, ClientHttpResponseError, ClientDecodeJsonError)
  , ServiceError(ServiceOtherError)
  )
import Control.Alt (class Alt)
import Control.Alternative (class Alternative)
import Control.Monad.Error.Class (class MonadError, class MonadThrow)
import Control.Monad.Logger.Class (class MonadLogger)
import Control.Monad.Reader.Class (class MonadAsk, class MonadReader)
import Control.Monad.Reader.Trans (ReaderT(ReaderT), asks)
import Control.Monad.Rec.Class (class MonadRec)
import Control.Parallel (class Parallel, parallel, sequential)
import Control.Plus (class Plus)
import Cardano.Kupmios.Helpers (logWithLevel)
import Cardano.Kupmios.KupmiosM.HttpUtils (handleAffjaxResponseGeneric)

import Cardano.Provider.ServerConfig (ServerConfig)
import Data.Either (Either)
import Data.Log.Level (LogLevel)
import Data.Log.Message (Message)
import Data.Maybe (Maybe, fromMaybe)
import Data.Newtype (class Newtype, unwrap, wrap)
import Effect.Aff (Aff, ParAff)
import Effect.Aff.Class (class MonadAff, liftAff)
import Effect.Class (class MonadEffect)
import Effect.Exception (Error)

-- | `KupmiosConfig` contains a complete specification on how to initialize a
-- | `KupmiosM` environment.
-- | It includes:
-- | - server parameters for all the services
-- | - network ID
-- | - logging level
-- | - optional custom logger
type KupmiosConfig =
  { ogmiosConfig :: ServerConfig
  , kupoConfig :: ServerConfig
  , logLevel :: LogLevel
  , customLogger :: Maybe (LogLevel -> Message -> Aff Unit)
  , suppressLogs :: Boolean
  }

-- | `KupmiosEnv` contains everything needed for `KupmiosM` to run.
type KupmiosEnv =
  { config :: KupmiosConfig
  }

type KupmiosM = KupmiosMT Aff

type ParKupmiosM = KupmiosMT ParAff

newtype KupmiosMT (m :: Type -> Type) (a :: Type) =
  KupmiosMT (ReaderT KupmiosEnv m a)

derive instance Newtype (KupmiosMT m a) _
derive newtype instance Functor m => Functor (KupmiosMT m)
derive newtype instance Apply m => Apply (KupmiosMT m)
derive newtype instance Applicative m => Applicative (KupmiosMT m)
derive newtype instance Bind m => Bind (KupmiosMT m)
derive newtype instance Alt m => Alt (KupmiosMT m)
derive newtype instance Plus m => Plus (KupmiosMT m)
derive newtype instance Alternative m => Alternative (KupmiosMT m)
derive newtype instance Monad (KupmiosMT Aff)
derive newtype instance MonadEffect (KupmiosMT Aff)
derive newtype instance MonadAff (KupmiosMT Aff)
derive newtype instance
  ( Semigroup a
  , Apply m
  ) =>
  Semigroup (KupmiosMT m a)

derive newtype instance
  ( Monoid a
  , Applicative m
  ) =>
  Monoid (KupmiosMT m a)

derive newtype instance MonadThrow Error (KupmiosMT Aff)
derive newtype instance MonadError Error (KupmiosMT Aff)
derive newtype instance MonadRec (KupmiosMT Aff)
derive newtype instance MonadAsk KupmiosEnv (KupmiosMT Aff)
derive newtype instance MonadReader KupmiosEnv (KupmiosMT Aff)

instance MonadLogger (KupmiosMT Aff) where
  log msg = do
    config <- asks $ _.config
    let
      logFunction =
        config # _.customLogger >>> fromMaybe logWithLevel
    liftAff $ logFunction config.logLevel msg

-- Newtype deriving complains about overlapping instances, so we wrap and
-- unwrap manually
instance Parallel (KupmiosMT ParAff) (KupmiosMT Aff) where
  parallel :: KupmiosMT Aff ~> KupmiosMT ParAff
  parallel = wrap <<< parallel <<< unwrap
  sequential :: KupmiosMT ParAff ~> KupmiosMT Aff
  sequential = wrap <<< sequential <<< unwrap

handleAffjaxResponse
  :: forall (result :: Type)
   . DecodeAeson result
  => Either Affjax.Error (Affjax.Response String)
  -> Either ClientError result
handleAffjaxResponse =
  handleAffjaxResponseGeneric
    { httpError: ClientHttpError
    , httpStatusCodeError: \statusCode body -> ClientHttpResponseError
        (wrap statusCode)
        (ServiceOtherError body)
    , decodeError: ClientDecodeJsonError
    , parse: (decodeAeson <=< parseJsonStringToAeson)
    , transform: pure
    }
