module Enemy.All.Boss.HopProjectile
    ( mkHopProjectile
    ) where

import Control.Monad.IO.Class (MonadIO)
import Data.Maybe             (fromMaybe)
import qualified Data.Set as S

import Attack
import Attack.Hit
import Collision
import Constants
import Enemy.All.Boss.AttackDescriptions
import Enemy.All.Boss.Data
import FileCache
import Id
import Msg
import Particle.All.Simple
import Projectile as P
import Util
import Window.Graphics
import World.Surface.Types
import World.ZIndex

packPath             = \f -> PackResourceFilePath "data/enemies/boss-enemy-attack2.pack" f
projDisappearSprPath = packPath "attack-hop-projectile-disappear.spr" :: PackResourceFilePath
projHitSprPath       = packPath "attack-hop-projectile-hit.spr"       :: PackResourceFilePath

projHitSoundPath = "event:/SFX Events/Enemy/Boss/attack-hop-hit" :: FilePath

hopProjectileOffset = Pos2 150.0 (-131.0) :: Pos2

data HopProjectileData = HopProjectileData
    { _attack :: Attack
    }

mkHopProjectileData :: Attack -> HopProjectileData
mkHopProjectileData atk = HopProjectileData
    { _attack = atk
    }

mkHopProjectile :: MonadIO m => Pos2 -> Direction -> BossEnemyData -> m (Some Projectile)
mkHopProjectile enemyPos dir enemyData =
    let
        releaseHopProjOffset = hopProjectileOffset `vecFlip` dir
        pos                  = enemyPos `vecAdd` releaseHopProjOffset
        atkDesc              = _hopProjectile $ _attackDescs enemyData
    in do
        atk <- mkAttack pos dir atkDesc
        let
            vel         = attackVelToVel2 (attackVel atk) zeroVel2
            hopProjData = mkHopProjectileData atk

        msgId  <- newId
        let hbx = fromMaybe (DummyHitbox pos) (attackHitbox atk)
        return . Some $ (mkProjectile hopProjData msgId hbx maxSecs)
            { _vel                  = vel
            , _registeredCollisions = S.fromList [ProjRegisteredPlayerCollision, ProjRegisteredSurfaceCollision]
            , _think                = thinkHopProjectile
            , _update               = updateHopProjectile
            , _draw                 = drawHopProjectile
            , _processCollisions    = processCollisions
            }

thinkHopProjectile :: Monad m => ProjectileThink HopProjectileData m
thinkHopProjectile hopProj = return $ thinkAttack atk
    where atk = _attack (_data hopProj :: HopProjectileData)

updateHopProjectile :: Monad m => ProjectileUpdate HopProjectileData m
updateHopProjectile hopProj = return $ hopProj
    { _data   = hopProjData'
    , _vel    = vel
    , _hitbox = const $ fromMaybe (DummyHitbox pos') (attackHitbox atk')
    , _ttl    = ttl
    }
    where
        hopProjData = _data hopProj
        atk         = _attack (hopProjData :: HopProjectileData)
        pos         = _pos (atk :: Attack)
        vel         = attackVelToVel2 (attackVel atk) zeroVel2
        pos'        = pos `vecAdd` (toPos2 $ vel `vecMul` timeStep)
        dir         = _dir (atk :: Attack)

        atk'         = updateAttack pos' dir atk
        ttl          = if _done atk' then 0.0 else _ttl hopProj
        hopProjData' = hopProjData {_attack = atk'} :: HopProjectileData

processCollisions :: ProjectileProcessCollisions HopProjectileData
processCollisions collisions hopProj = foldr processCollision [] collisions
    where
        processCollision :: ProjectileCollision -> [Msg ThinkCollisionMsgsPhase] -> [Msg ThinkCollisionMsgsPhase]
        processCollision pc msgs = case pc of
            ProjPlayerCollision player              -> playerCollision player hopProj ++ msgs
            ProjSurfaceCollision hbx GeneralSurface -> surfaceCollision hbx hopProj ++ msgs
            _                                       -> msgs

playerCollision :: CollisionEntity e => e -> Projectile HopProjectileData -> [Msg ThinkCollisionMsgsPhase]
playerCollision player hopProj =
    [ mkMsgTo (HurtMsgAttackHit atkHit) playerId
    , mkMsgTo (ProjectileMsgSetTtl 0.0) hopProjId
    , mkMsg $ ParticleMsgAddM mkHitEffect
    , mkMsg $ AudioMsgPlaySound projHitSoundPath pos
    ]
        where
            playerId    = collisionEntityMsgId player
            hopProjId   = P._msgId hopProj
            atk         = _attack (_data hopProj :: HopProjectileData)
            atkHit      = mkAttackHit atk
            pos         = _pos (atk :: Attack)
            dir         = _dir (atk :: Attack)
            mkHitEffect = loadSimpleParticle pos dir enemyAttackProjectileZIndex projHitSprPath

surfaceCollision :: Hitbox -> Projectile HopProjectileData -> [Msg ThinkCollisionMsgsPhase]
surfaceCollision surfaceHbx hopProj
    | hitboxTop surfaceHbx <= hitboxTop hopProjHbx =  -- crude wall/non-ground check
        [ mkMsgTo (ProjectileMsgSetTtl 0.0) hopProjId
        , mkMsg $ ParticleMsgAddM mkDisappearEffect
        ]
    | otherwise                                    = []
        where
            hopProjHbx        = (P._hitbox hopProj) hopProj
            hopProjId         = P._msgId hopProj
            atk               = _attack (_data hopProj :: HopProjectileData)
            pos               = _pos (atk :: Attack)
            dir               = _dir (atk :: Attack)
            mkDisappearEffect = loadSimpleParticle pos dir enemyAttackProjectileZIndex projDisappearSprPath

drawHopProjectile :: (GraphicsReadWrite m, MonadIO m) => ProjectileDraw HopProjectileData m
drawHopProjectile hopProj =
    let
        attack = _attack (_data hopProj :: HopProjectileData)
        spr    = attackSprite attack
        pos    = _pos (attack :: Attack)
        vel    = P._vel hopProj
        dir    = _dir (attack :: Attack)
    in do
        pos' <- graphicsLerpPos pos vel
        drawSprite pos' dir enemyAttackProjectileZIndex spr
