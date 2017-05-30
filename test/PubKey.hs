module PubKey where

import TestPrelude
import Test.Hspec
import qualified Network.Haskoin.Test     as HTT
import qualified Network.Haskoin.Crypto   as HC
import qualified ChanDB                   as DB
import           ChanDB.PubKey               (External, ChildPub, fromXPub, pairPub)
import qualified ChanDB                   as PK
    ( pubKeySetup
    , pubKeyCurrent
    , pubKeyLookup
    , pubKeyMarkUsed
    , pubKeyDELETE
    , KeyAtIndex(..)
    , CurrentKey(..)
    , RecvPubKey(..)
    )



logLevel = DB.LevelInfo

maxKeysGen :: Int
maxKeysGen = 100

minKeysGen :: Int
minKeysGen = 0

pubKeySpec :: Spec
pubKeySpec =
  around withArbPubKey $ do
    describe "current key" $ do
      it "has derive_index=0 when just initialized" $ \(h,xpub) ->
        keyIndex <$> dbRun h (PK.pubKeyCurrent xpub) `shouldReturn` 0

      it "has derive_index=<n> after marking <n> keys as used" $ \(h,xpub) -> do
        genCount <- generate (choose (minKeysGen, maxKeysGen) :: Gen Int)
        genCount `timesDo` getAndMarkUsed h xpub
        keyIndex <$> dbRun h (PK.pubKeyCurrent xpub) `shouldReturn` genCount

    describe "lookup by pubkey" $
      it "can fetch derive_index for any generated pubkey" $ \(h,xpub) -> do
        genCount  <- generate (choose (minKeysGen, maxKeysGen) :: Gen Int)
        genCount `timesDo` getAndMarkUsed h xpub
        rndKeyIdx <- generate (choose (0, genCount) :: Gen Int)
        let rndIdxPk = PK.MkRecvPubKey . snd $ HC.deriveAddr (pairPub xpub) (fromIntegral rndKeyIdx)
        fmap keyIndex <$> dbRun h (PK.pubKeyLookup xpub rndIdxPk) `shouldReturn` Just rndKeyIdx


keyIndex = fromIntegral . PK.kaiIndex
timesDo c f = forM_ (take c [0..]) (const f)

getAndMarkUsed :: DB.ChanDB DB.Impl h => h -> External ChildPub -> IO ()
getAndMarkUsed h xpub = do
    kai <- dbRun h $ PK.pubKeyCurrent xpub
    void $ dbRun h $ PK.pubKeyMarkUsed xpub (PK.kaiPubKey kai)

dbRun :: DB.ChanDB DB.Impl h => h -> DB.Impl a -> IO a
dbRun h m = failLeft <$> DB.runDB h m

main :: IO ()
main = hspec pubKeySpec


pkAlloc :: DB.ChanDB DB.Impl h => h -> External ChildPub -> IO (External ChildPub)
pkAlloc h xpub = dbRun h (PK.pubKeySetup xpub) >> return xpub

pkCleanup :: DB.ChanDB DB.Impl h => h -> External ChildPub -> IO ()
pkCleanup h xpub = dbRun h (PK.pubKeyDELETE xpub)

withArbPubKey :: DB.ChanDB DB.Impl h => ((h, External ChildPub) -> IO ()) -> IO ()
withArbPubKey f = do
    dbHandle <- DB.getHandle stdout logLevel
    HTT.ArbitraryXPubKey _ xpub <- generate arbitrary
    bracket
        (pkAlloc dbHandle (fromXPub xpub))
        (pkCleanup dbHandle)
        (\pk -> f (dbHandle, pk))

failLeft :: Show e => Either e a -> a
failLeft = either (error . show) id
