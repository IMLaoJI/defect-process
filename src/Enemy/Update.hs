module Enemy.Update
    ( updateEnemy
    ) where

import Control.Monad.IO.Class (MonadIO)
import Control.Monad.State    (get, execStateT, lift, modify, put)
import Data.Dynamic           (toDyn)
import Data.Foldable          (foldlM)
import qualified Data.List as L
import qualified Data.Set as S

import AppEnv
import Attack
import Attack.Hit
import Collision
import Configs
import Configs.All.Settings
import Configs.All.Settings.Debug
import Constants
import Enemy as E
import Enemy.DebugText
import Msg
import Util
import World.Surface

roofOffsetY            = 1.0  :: Float
maxOnPlatformDistanceY = 25.0 :: PosY

updateEnemyMessages :: Enemy d -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
updateEnemyMessages enemy =
    processAiMessages enemy >>=
    processCollisionMessages >>=
    processEnemyMessages >>=
    processHurtMessages

updateEnemyWall :: PosX -> WallSurfaceType -> Enemy d -> Enemy d
updateEnemyWall wallX wallType enemy = enemy
    { _pos   = Pos2 (x + xOffset) y
    , _flags = (_flags enemy)
        { _touchingLeftWall  = wallType == LeftWallSurface
        , _touchingRightWall = wallType == RightWallSurface
        }
    }
    where
        Pos2 x y = E._pos enemy
        hbx      = enemyHitbox enemy
        hbxLeft  = hitboxLeft hbx
        hbxRight = hitboxRight hbx
        xOffset  = case wallType of
            LeftWallSurface
                | hbxLeft < wallX  -> wallX - hbxLeft
                | otherwise        -> 0.0
            RightWallSurface
                | hbxRight > wallX -> wallX - hbxRight
                | otherwise        -> 0.0

updateEnemyRoof :: PosY -> Enemy d -> Enemy d
updateEnemyRoof roofY enemy = enemy
    { _pos = Pos2 x (roofY + hitboxHeight hitbox + roofOffsetY)
    , _vel = Vel2 velX (if velY < 0.0 then 0.0 else velY)
    }
    where
        x              = vecX $ E._pos enemy
        Vel2 velX velY = E._vel enemy
        hitbox         = enemyHitbox enemy

updateEnemyWillFallOffGround :: Enemy d -> Enemy d
updateEnemyWillFallOffGround enemy = enemy
    { _flags = (_flags enemy) {_willFallOffGround = True}
    }

updateEnemyPosVel :: Enemy d -> Enemy d
updateEnemyPosVel enemy = enemy
    { _pos           = pos
    , _vel           = vel'
    , _launchTargetY = launchTargetY'
    }
    where
        vel            = E._vel enemy
        pos@(Pos2 _ y) = E._pos enemy `vecAdd` toPos2 (vel `vecMul` timeStep)
        launchTargetY  = E._launchTargetY enemy
        vel'           = case launchTargetY of
            Just minY
                | y <= minY -> zeroVel2
            _               -> vel

        launchTargetY'
            | vecY vel' >= 0.0 = Nothing
            | otherwise        = launchTargetY

updateEnemyAttack :: Enemy d -> Enemy d
updateEnemyAttack enemy = enemy
    { _attack = attack
    , _vel    = vel'
    }
    where
        pos            = E._pos enemy
        vel            = E._vel enemy
        dir            = E._dir enemy
        (attack, vel') = case _attack enemy of
            Nothing  -> (Nothing, vel)
            Just atk ->
                let
                    atk'   = updateAttack pos dir atk
                    atkVel = attackVel atk'
                in (Just atk', attackVelToVel2 atkVel vel)

updateEnemyDebug :: ConfigsRead m => Enemy d -> m (Enemy d)
updateEnemyDebug enemy = do
    debugCfg <- readConfig _settings _debug
    return $ enemy
        { _debugText   = updateEnemyDebugText (_health enemy) <$> _debugText enemy
        , _debugConfig = debugCfg
        }

updateEnemy :: Enemy d -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
updateEnemy enemy = flip execStateT enemy $ do
    modify $ \e -> e {_flags = clearEnemyFlags (_flags e)}
    get >>= lift . updateEnemyMessages >>= put
    modify updateEnemyAttack
    modify updateEnemyPosVel
    modify $ \e -> (_updateSprite e) e
    get >>= lift . updateEnemyDebug >>= put

processAiMessages :: MsgsRead UpdateEnemyMsgsPhase m => Enemy d -> m (Enemy d)
processAiMessages enemy = L.foldl' processMsg enemy <$> readMsgsTo (_msgId enemy)
    where
        processMsg :: Enemy d -> InfoMsgPayload -> Enemy d
        processMsg e d = case d of
            InfoMsgSeenPlayer playerInfo -> e {_knownPlayerInfo = playerInfo}
            _                            -> e

processCollisionMessages :: Enemy d -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
processCollisionMessages enemy = foldlM processMsg enemy =<< readMsgsTo (_msgId enemy)
    where
        updateEnemyGroundResponse :: PosY -> SurfaceType -> Enemy d -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
        updateEnemyGroundResponse groundY surfaceType e = case surfaceType of
            GeneralSurface     -> groundResponse
            PlatformSurface
                | onPlatform   -> groundResponse
                | otherwise    -> return e
            SpeedRailSurface _ -> groundResponse
            where
                y              = vecY $ E._pos e
                onPlatform     = abs (groundY - y) <= maxOnPlatformDistanceY
                groundResponse = (_updateGroundResponse e) groundY e

        processMsg :: Enemy d -> CollisionMsgPayload -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
        processMsg e d = case d of
            CollisionMsgTouchingGround groundY surfaceType -> updateEnemyGroundResponse groundY surfaceType e
            CollisionMsgTouchingWall groundX _ wallType    -> return $ updateEnemyWall groundX wallType e
            CollisionMsgTouchingRoof roofY                 -> return $ updateEnemyRoof roofY e
            CollisionMsgWillFallOffGround                  -> return $ updateEnemyWillFallOffGround e
            CollisionMsgMovingPlatform _ _                 -> return e
            CollisionMsgWallProximity _ _                  -> return e

processEnemyMessages :: Enemy d -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
processEnemyMessages enemy = foldlM processMsg enemy =<< readMsgsTo (_msgId enemy)
    where
        processMsg :: Enemy d -> EnemyMsgPayload -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
        processMsg !e d = case d of
            EnemyMsgUpdate update            -> updateDynamic $ toDyn update
            EnemyMsgUpdateM update           -> updateDynamic $ toDyn update
            EnemyMsgSetVelocity vel          -> return $ e {E._vel = vel}
            EnemyMsgUpdateVelocity update    -> return $ e {E._vel = update $ E._vel e}
            EnemyMsgSetDirection dir'        -> return $ e {E._dir = dir'}
            EnemyMsgClearAttack              -> return $ e {_attack = Nothing}
            EnemyMsgFinishAttack             -> return $ e {_attack = finishAttack <$> _attack e}
            EnemyMsgSetAttackDesc atkDesc    -> setAttackDesc e atkDesc
            EnemyMsgSetAttackDescM atkDesc   -> setAttackDesc e =<< atkDesc
            EnemyMsgSetDead                  -> return $ e {_flags = (_flags e) {_dead = True}}
            EnemyMsgSetHangtime hangtimeSecs -> return $ (_updateHangtimeResponse e) hangtimeSecs e
            EnemyMsgAddM _                   -> return e
            EnemyMsgAdds _                   -> return e
            EnemyMsgAddsM _                  -> return e
            where updateDynamic = \dyn -> (_updateDynamic e) dyn e

        setAttackDesc :: MonadIO m => Enemy d -> AttackDescription -> m (Enemy d)
        setAttackDesc e atkDesc =
            let
                pos = E._pos e
                dir = E._dir e
            in do
                enemyAtk <- mkAttack pos dir atkDesc
                return $ e {_attack = Just enemyAtk}

hurtEnemy :: AttackHit -> Enemy d -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
hurtEnemy atkHit enemy = do
    damageMultiplier <- readSettingsConfig _debug _enemiesDamageMultiplier

    let
        Damage damageVal = _damage (atkHit :: AttackHit)
        damageVal'       = ceiling $ fromIntegral damageVal * damageMultiplier
        atkHit'          = atkHit {_damage = Damage damageVal'} :: AttackHit
        atkHashedId      = _hashedId atkHit'
        hitByHashedIds   = _hitByHashedIds enemy

    if
        | atkHashedId `S.member` hitByHashedIds -> return enemy
        | otherwise                             -> do
            enemy' <- (_updateHurtResponse enemy) atkHit' enemy
            return $ enemy' {_hitByHashedIds = atkHashedId `S.insert` hitByHashedIds}

processHurtMessages :: Enemy d -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
processHurtMessages enemy = foldlM processMsg enemy =<< readMsgsTo (_msgId enemy)
    where
        processMsg :: Enemy d -> HurtMsgPayload -> AppEnv UpdateEnemyMsgsPhase (Enemy d)
        processMsg e d = case d of
            HurtMsgAttackHit atkHit -> hurtEnemy atkHit e
