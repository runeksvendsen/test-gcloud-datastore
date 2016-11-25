{-# LANGUAGE DataKinds #-}
module Types
(
  module Types
-- , module Network.Google
-- , module Network.Google.Datastore
, Pay.SendPubKey
, PromissoryNote, Note, UUID
, Pay.PayChanError
, Pay.BitcoinAmount
, Catch.MonadCatch
, MonadIO
, BS.ByteString
, T.Text
, Int64
, Tagged(..)
)
where


import qualified Data.Bitcoin.PaymentChannel.Test as Pay
import           PromissoryNote                   (PromissoryNote, UUID)

import           Data.Tagged (Tagged(..))
import           Control.Monad.IO.Class     (MonadIO)
import qualified Control.Monad.Catch as      Catch

import           Data.ByteString as BS
import           Data.Int                         (Int64)
import qualified Data.Text                      as T


type Note = PromissoryNote
type RecvPayChan = Pay.RecvPayChanX
type ProjectId = T.Text

type AuthCloudPlatform = "https://www.googleapis.com/auth/cloud-platform"
type AuthDatastore = "https://www.googleapis.com/auth/datastore"
