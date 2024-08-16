{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module API.Endpoints
  ( api
  , server
  ) where

import           Control.Monad.IO.Class     (MonadIO (liftIO))
import           Data.Bool                  (bool)
import qualified Data.ByteString.Char8      as BS
import qualified Data.ByteString.Lazy.Char8 as LBS
import           DataTypes                  (HealthCheck (..))
import           Helpers                    (initLogger, logInfo)
import           Infrastructure.Config      (loadBoltCfg)
import           Infrastructure.Database    (checkNeo4j, getReaction, withNeo4j)
import           Models                     (ReactionDetails)
import           Network.HTTP.Types.Header  (hContentType)
import           Prelude                    hiding (id)
import qualified Servant                    as S

type API =
  "health" S.:> S.Get '[ S.JSON] (S.Headers '[ S.Header "Content-Type" String] HealthCheck) S.:<|> 
  "reaction" S.:> S.Capture "id" Int S.:> S.Get '[ S.JSON] (S.Headers '[ S.Header "Content-Type" String] ReactionDetails)

api :: S.Proxy API
api = S.Proxy

healthHandler ::
     S.Handler (S.Headers '[ S.Header "Content-Type" String] HealthCheck)
healthHandler = do
  logger <- liftIO initLogger
  boltCfg <- liftIO loadBoltCfg
  neo4jStatus <- (liftIO . withNeo4j boltCfg) checkNeo4j
  let neo4jMessage = bool "Neo4j is down" "Neo4j is alive" neo4jStatus
  let health = HealthCheck {status = "Server is alive", neo4j = neo4jMessage}
  (liftIO . logInfo logger . show) health
  if neo4jStatus
    then return $ S.addHeader "application/json" health
    else S.throwError
           S.err500
             { S.errBody = LBS.pack "Neo4j is down"
             , S.errHeaders = [(hContentType, BS.pack "application/json")]
             }

reactionHandler ::
     Int
  -> S.Handler (S.Headers '[ S.Header "Content-Type" String] ReactionDetails)
reactionHandler id = do
  logger <- liftIO initLogger
  boltCfg <- liftIO loadBoltCfg
  result <- liftIO . withNeo4j boltCfg $ getReaction id
  (liftIO . logInfo logger . show) result
  return $ S.addHeader "application/json" result

server :: S.Server API
server = healthHandler S.:<|> reactionHandler
