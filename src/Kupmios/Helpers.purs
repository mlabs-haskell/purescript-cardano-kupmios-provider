module Cardano.Kupmios.Helpers where

import Prelude

import Control.Monad.Error.Class (class MonadThrow, liftEither, throwError)
import Data.Either (Either(Right))
import Data.JSDate (now)
import Data.Log.Formatter.Pretty (prettyFormatter)
import Data.Log.Level (LogLevel)
import Data.Log.Message (Message)
import Data.Map as Map
import Data.Maybe (Maybe, maybe)
import Effect (Effect)
import Effect.Class (class MonadEffect)
import Effect.Class.Console (log)

-- | Log a message by printing it to the console, depending on the provided
-- | `LogLevel`
logWithLevel
  :: forall (m :: Type -> Type). MonadEffect m => LogLevel -> Message -> m Unit
logWithLevel lvl msg = when (msg.level >= lvl) $ log =<< prettyFormatter msg

-- | Log a message from the JS side of the FFI boundary. The first `LogLevel`
-- | argument represents the configured log level (e.g. within `QueryConfig`).
-- | The second argument is the level for this particular message
logString :: LogLevel -> LogLevel -> String -> Effect Unit
logString cfgLevel level message = do
  timestamp <- now
  logWithLevel cfgLevel { timestamp, message, level, tags: Map.empty }

-- | Given an error and a `Maybe` value, lift the context via `liftEither`.
liftM
  :: forall (e :: Type) (m :: Type -> Type) (a :: Type)
   . MonadThrow e m
  => e
  -> Maybe a
  -> m a
liftM err = liftEither <<< maybe (throwError err) Right
