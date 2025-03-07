module Cardano.Kupmios.Logging (Logger, mkLogger, logTrace') where

import Prelude

import Cardano.Kupmios.Helpers (logString)
import Control.Monad.Logger.Class (class MonadLogger)
import Control.Monad.Logger.Class as Logger
import Data.JSDate (now)
import Data.Log.Level (LogLevel)
import Data.Log.Message (Message)
import Data.Map as Map
import Data.Maybe (Maybe(Just, Nothing))
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)

type Logger = LogLevel -> String -> Effect Unit

mkLogger
  :: LogLevel
  -> Maybe (LogLevel -> Message -> Aff Unit)
  -> Logger
mkLogger logLevel mbCustomLogger level message =
  case mbCustomLogger of
    Nothing -> logString logLevel level message
    Just logger -> liftEffect do
      timestamp <- now
      launchAff_ $ logger logLevel
        { level, message, tags: Map.empty, timestamp }

logTrace'
  :: forall (m :: Type -> Type). MonadLogger m => String -> m Unit
logTrace' = Logger.trace Map.empty
