module Cardano.Kupmios.QueryM.Ogmios.Helpers
  ( sysStartFromOgmiosTimestamp
  , sysStartFromOgmiosTimestampUnsafe
  , sysStartToOgmiosTimestamp
  ) where

import Prelude

import Cardano.Types.SystemStart (SystemStart)
import Control.Alt ((<|>))
import Data.DateTime (DateTime)
import Data.Either (Either, hush)
import Data.Formatter.DateTime (Formatter, format, parseFormatString, unformat)
import Data.Maybe (Maybe(Just, Nothing))
import Data.Newtype (unwrap, wrap)
import Data.String (length, take) as String
import Effect.Exception (throw)
import Effect.Unsafe (unsafePerformEffect)

-- | Attempts to parse `SystemStart` from Ogmios timestamp string.
sysStartFromOgmiosTimestamp :: String -> Either String SystemStart
sysStartFromOgmiosTimestamp timestamp = wrap <$> (unformatMsec <|> unformatSec)
  where
  unformatMsec :: Either String DateTime
  unformatMsec = unformat
    (mkDateTimeFormatterUnsafe ogmiosDateTimeFormatStringMsec)
    (String.take (String.length ogmiosDateTimeFormatStringMsec) timestamp)

  unformatSec :: Either String DateTime
  unformatSec = unformat
    (mkDateTimeFormatterUnsafe ogmiosDateTimeFormatStringSec)
    (String.take (String.length ogmiosDateTimeFormatStringSec) timestamp)

sysStartFromOgmiosTimestampUnsafe :: String -> SystemStart
sysStartFromOgmiosTimestampUnsafe timestamp =
  unsafeFromJust "sysStartFromOgmiosTimestampUnsafe" $ hush $
    sysStartFromOgmiosTimestamp timestamp

sysStartToOgmiosTimestamp :: SystemStart -> String
sysStartToOgmiosTimestamp =
  format (mkDateTimeFormatterUnsafe ogmiosDateTimeFormatStringMsecUTC)
    <<< unwrap

mkDateTimeFormatterUnsafe :: String -> Formatter
mkDateTimeFormatterUnsafe =
  unsafeFromJust "mkDateTimeFormatterUnsafe" <<< hush <<< parseFormatString

ogmiosDateTimeFormatStringSec :: String
ogmiosDateTimeFormatStringSec = "YYYY-MM-DDTHH:mm:ss"

ogmiosDateTimeFormatStringMsec :: String
ogmiosDateTimeFormatStringMsec = ogmiosDateTimeFormatStringSec <> ".SSS"

ogmiosDateTimeFormatStringMsecUTC :: String
ogmiosDateTimeFormatStringMsecUTC = ogmiosDateTimeFormatStringMsec <> "Z"

unsafeFromJust :: forall a. String -> Maybe a -> a
unsafeFromJust e a = case a of
  Nothing ->
    unsafePerformEffect $ throw $ "unsafeFromJust: impossible happened: "
      <> e
      <> " (please report as bug at "
      <> bugTrackerLink
      <> " )"
  Just v -> v

bugTrackerLink :: String
bugTrackerLink =
  "https://github.com/Plutonomicon/cardano-transaction-lib/issues"
