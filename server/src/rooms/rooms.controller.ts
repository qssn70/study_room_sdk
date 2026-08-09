import {
  Body,
  Controller,
  Delete,
  Get,
  HttpCode,
  Param,
  Patch,
  ParseUUIDPipe,
  Post,
  Put,
  Query,
} from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { CreateRoomDto, DecideJoinRequestDto, RoomPageQueryDto, TransferOwnershipDto } from './rooms.dto';
import { RoomsService } from './rooms.service';

@ApiTags('rooms')
@ApiBearerAuth()
@Controller('v1')
export class RoomsController {
  constructor(private readonly rooms: RoomsService, private readonly realtime: RealtimePublisher) {}

  @Post('rooms')
  async create(@Body() body: CreateRoomDto, @CurrentIdentity() identity: ExternalIdentity) {
    const room = await this.rooms.create(body.title, identity);
    this.realtime.publishRoom(identity.appId, room.id, 'room.state', room, room.version);
    return room;
  }

  @Get('rooms')
  list(
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: RoomPageQueryDto,
  ) {
    return this.rooms.list(identity, query.cursor, query.limit);
  }

  @Get('rooms/:roomId')
  get(@Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string, @CurrentIdentity() identity: ExternalIdentity) {
    return this.rooms.get(roomId, identity);
  }

  @Post('rooms/:roomId/join-requests')
  async requestJoin(@Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string, @CurrentIdentity() identity: ExternalIdentity) {
    const request = await this.rooms.requestJoin(roomId, identity);
    const ownerUserId = await this.rooms.ownerUserId(roomId, identity.appId);
    this.realtime.publishUser(
      identity.appId,
      ownerUserId,
      'join-request.created',
      request,
      roomId,
      null,
    );
    return request;
  }

  @Get('join-requests')
  myRequests(
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: RoomPageQueryDto,
  ) {
    return this.rooms.listMyJoinRequests(identity, query.cursor, query.limit);
  }

  @Get('rooms/:roomId/join-requests')
  roomRequests(
    @Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: RoomPageQueryDto,
  ) {
    return this.rooms.listRoomJoinRequests(roomId, identity, query.cursor, query.limit);
  }

  @Delete('rooms/:roomId/join-requests')
  @HttpCode(204)
  async cancelRequest(@Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string, @CurrentIdentity() identity: ExternalIdentity) {
    await this.rooms.cancelJoinRequest(roomId, identity);
  }

  @Patch('rooms/:roomId/join-requests/:requestId')
  async decideRequest(
    @Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string,
    @Param('requestId', new ParseUUIDPipe({ version: '4' })) requestId: string,
    @Body() body: DecideJoinRequestDto,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const result = await this.rooms.decideJoinRequest(roomId, requestId, body.decision, identity);
    this.realtime.publishUser(
      identity.appId,
      result.request.userId,
      'join-request.updated',
      result.request,
      roomId,
      null,
    );
    if (result.roomVersion) {
      const room = await this.rooms.snapshot(identity.appId, roomId);
      if (room) this.realtime.publishRoom(identity.appId, roomId, 'room.state', room, room.version);
    }
    return result.request;
  }

  @Delete('rooms/:roomId/members/me')
  @HttpCode(204)
  async leave(@Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string, @CurrentIdentity() identity: ExternalIdentity) {
    const room = await this.rooms.leave(roomId, identity);
    await this.realtime.evictUser(identity.appId, roomId, identity.userId);
    this.realtime.publishUser(identity.appId, identity.userId, 'membership.updated', { roomId, active: false }, roomId, room.version);
    this.realtime.publishRoom(identity.appId, roomId, 'room.state', room, room.version);
  }

  @Delete('rooms/:roomId/members/:userId')
  @HttpCode(204)
  async removeMember(
    @Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string,
    @Param('userId') userId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const room = await this.rooms.removeMember(roomId, userId, identity);
    this.realtime.publishUser(identity.appId, userId, 'membership.updated', { roomId, active: false }, roomId, room.version);
    await this.realtime.evictUser(identity.appId, roomId, userId);
    this.realtime.publishRoom(identity.appId, roomId, 'room.state', room, room.version);
  }

  @Put('rooms/:roomId/owner')
  async transferOwner(
    @Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string,
    @Body() body: TransferOwnershipDto,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const room = await this.rooms.transferOwnership(roomId, body.userId, identity);
    this.realtime.publishRoom(identity.appId, roomId, 'room.state', room, room.version);
    return room;
  }

  @Delete('rooms/:roomId')
  @HttpCode(204)
  async delete(@Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string, @CurrentIdentity() identity: ExternalIdentity) {
    const { userIds, roomVersion } = await this.rooms.delete(roomId, identity);
    for (const userId of userIds) {
      this.realtime.publishUser(identity.appId, userId, 'membership.updated', { roomId, active: false }, roomId, roomVersion);
      await this.realtime.evictUser(identity.appId, roomId, userId);
    }
  }
}
