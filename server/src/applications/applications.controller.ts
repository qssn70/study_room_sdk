import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AdminScope } from '../auth/auth.decorators';
import { CurrentAdmin } from '../auth/current-admin.decorator';
import { AdminIdentity } from '../domain';
import { PaginationQueryDto } from '../common/pagination.dto';
import { CreateApplicationDto, UpdateApplicationDto } from './application.dto';
import { ApplicationsService } from './applications.service';

@ApiTags('applications')
@ApiBearerAuth()
@AdminScope('apps:manage')
@Controller('admin/v1/apps')
export class ApplicationsController {
  constructor(private readonly applications: ApplicationsService) {}

  @Post()
  create(@Body() body: CreateApplicationDto, @CurrentAdmin() admin: AdminIdentity) {
    return this.applications.create(body, admin.subject);
  }

  @Get()
  list(@Query() query: PaginationQueryDto) {
    return this.applications.list(query.cursor, query.limit);
  }

  @Get(':appId')
  get(@Param('appId') appId: string) {
    return this.applications.get(appId);
  }

  @Patch(':appId')
  update(
    @Param('appId') appId: string,
    @Body() body: UpdateApplicationDto,
    @CurrentAdmin() admin: AdminIdentity,
  ) {
    return this.applications.update(appId, body, admin.subject);
  }
}
