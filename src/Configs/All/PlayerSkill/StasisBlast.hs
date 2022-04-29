module Configs.All.PlayerSkill.StasisBlast
    ( StasisBlastConfig(..)
    ) where

import Data.Aeson.Types (FromJSON, genericParseJSON, parseJSON)
import GHC.Generics     (Generic)

import Util

data StasisBlastConfig = StasisBlastConfig
    { _blastCooldown   :: Secs
    , _blastStasisSecs :: Secs
    }
    deriving Generic

instance FromJSON StasisBlastConfig where
    parseJSON = genericParseJSON aesonFieldDropUnderscore
