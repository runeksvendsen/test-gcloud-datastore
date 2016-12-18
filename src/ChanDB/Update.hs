{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables, DeriveAnyClass, GADTs, FlexibleContexts, DataKinds #-}
module ChanDB.Update
(
  withDBState
, withDBStateNote
)
where

import           Util
import           ChanDB.Orphans ()
import           ChanDB.Types
import           DB.Query
import           PromissoryNote.StoredNote  (setMostRecentNote)
import           DB.Tx.Safe
import           DB.Request                 (txLookup, entityQuery, getFirstResult)
import qualified Network.Google.Datastore.Types as DS


type PayChanEnt = EntityAtKey RecvPayChan (EntityKey RecvPayChan)
type NoteEnt    = EntityAtKey StoredNote (EntityKey StoredNote)

txGetChanState :: NamespaceId
               -> TxId
               -> SendPubKey
               -> Datastore (Either UpdateErr RecvPayChan)
txGetChanState ns tx sendPK =
    getRes <$> lookup
  where
--     lookup :: Datastore ( Either String [(JustEntity RecvPayChan, EntityVersion)] )
    lookup = txLookup ns tx (sendPK <//> root :: WithAncestor RecvPayChan Void)


getRes :: Either String [ (JustEntity a, EntityVersion) ]
       -> Either UpdateErr a
getRes r =
    maybe (Left ChannelNotFound) Right (getFirstResult r) >>=
    \(JustEntity e) -> Right e


txGetLastNote :: NamespaceId
              -> TxId
              -> SendPubKey
              -> Datastore (Maybe StoredNote)
txGetLastNote ns tx k = do
    res <- entityQuery (Just ns) (Just tx) (qMostRecentNote k)
    return $ getRes' (res :: Either String [(NoteEnt, EntityVersion) ])
  where
    getRes' = fmap (\(EntityAtKey e _) -> e) . getFirstResult

qMostRecentNote :: SendPubKey
                -> AncestorQuery RecvPayChan (OfKind StoredNote (FilterProperty Bool Query))
qMostRecentNote k =
      AncestorQuery payChanId
    $ OfKind kind
    $ FilterProperty "most_recent_note" PFOEqual True
    query
  where
    kind = undefined :: StoredNote
    payChanId = getIdentifier k :: Ident RecvPayChan


withDBState :: NamespaceId
            -> SendPubKey
            -> (RecvPayChan -> Datastore (Either PayChanError RecvPayChan))
            -> Datastore (Either UpdateErr RecvPayChan)
withDBState ns sendPK f = do
    (eitherRes,_) <- withTx $ \tx -> do
        resE <- txGetChanState ns tx sendPK
        -- Apply user function
        let applyF chan = fmapL PayError <$> f chan
        applyResult <- either (return . Left) applyF resE
        -- Commit/rollback
        case applyResult of
            Left  _        -> return (applyResult, Nothing)
            Right newState -> do
                updChan <- mkMutation ns (Update $ EntityAtKey newState root)
                return ( applyResult, Just updChan )
    return $ case eitherRes of
        Right state -> Right state
        Left e -> Left e

withDBStateNote ::
               NamespaceId
            -> SendPubKey
            -> (   RecvPayChan
                -> Maybe StoredNote
                -> Datastore (Either PayChanError (RecvPayChan,StoredNote))
               )
            -> Datastore (Either UpdateErr RecvPayChan)
withDBStateNote ns sendPK f = do
    (eitherRes,_) <- withTx $ \tx -> do
        resE  <- txGetChanState ns tx sendPK
        noteM <- txGetLastNote ns tx sendPK
        -- Apply user function
        let applyF chan = fmapL PayError <$> f chan noteM
        applyResult <- either (return . Left) applyF resE
        -- Commit/rollback
        case applyResult of
            Left  _  ->
                return (applyResult , Nothing)
            Right (newState,newNote) -> do
                updChanNotes <- mkNoteCommit ns newState newNote noteM
                return (applyResult, Just updChanNotes)
    return $ case eitherRes of
        Right (state,_) -> Right state
        Left e -> Left e

mkNoteCommit :: NamespaceId
             -> RecvPayChan
             -> StoredNote
             -> Maybe StoredNote
             -> Datastore DS.CommitRequest
mkNoteCommit ns payChanState newNote prevNoteM = do
    updState    <- mkMutation ns (Update $ EntityAtKey payChanState root)
    insNewNote  <- mkMutation ns (Insert $ EntityAtKey newNote ancestor)
    -- If there's previous note: update it so its is_tip = False
    updPrevNote <- maybe (return mempty) updateNote prevNoteM
    return $ updState <> insNewNote <> updPrevNote
  where
    ancestor = getIdent payChanState
    updateNote n = mkMutation ns $ Update $
        EntityAtKey (setMostRecentNote False n) ancestor

