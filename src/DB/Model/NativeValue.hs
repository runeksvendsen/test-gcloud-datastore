{-# LANGUAGE ScopedTypeVariables #-}
module DB.Model.NativeValue
(
  module DB.Model.NativeValue
, Text
, ByteString
, Int64
)
where

import Network.Google.Datastore
import Control.Lens

import qualified Network.Google.Datastore.Types as DS
import           Data.Text          (Text)
import           Data.ByteString    (ByteString)
import           Data.Int           (Int64)
import           Data.Maybe         (fromMaybe)
import           Data.Typeable
import           Data.Scientific    (Scientific)


-- | A class for the value types inside a Datastore object
class Typeable a => NativeValue a where
    valueLens       :: Lens' DS.Value (Maybe a)
    encode          :: a -> DS.Value
    decode          :: DS.Value -> a
    decodeMaybe     :: DS.Value -> Maybe a

    encode a = set valueLens (Just a) value
    decodeMaybe = view valueLens
    decode v = fromMaybe
        ( error $ show (typeOf (undefined :: a)) ++ " not present in DS.Value: " ++ show v )
        (decodeMaybe v)

instance NativeValue Bool            where valueLens = vBooleanValue
instance NativeValue ByteString      where valueLens = vBlobValue
instance NativeValue Text            where valueLens = vStringValue
instance NativeValue Int64           where valueLens = vIntegerValue
instance NativeValue Double          where valueLens = vDoubleValue
instance NativeValue DS.Key          where valueLens = vKeyValue
instance NativeValue DS.Entity       where valueLens = vEntityValue
instance NativeValue DS.ArrayValue   where valueLens = vArrayValue
instance NativeValue DS.ValueNullValue where valueLens = vNullValue
