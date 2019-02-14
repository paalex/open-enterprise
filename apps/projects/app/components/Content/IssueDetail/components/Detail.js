import React from 'react'
import styled from 'styled-components'
import { Badge, Text, theme, ContextMenu, ContextMenuItem } from '@aragon/ui'

import { DropDownButton } from '../../../Shared'
import githubLogo from '../../../../assets/svg/github.svg'

const GithubLogo = styled.img`
  height: 1em;
  vertical-align: middle;
  margin-right: 5px;
  filter: invert(59%) sepia(21%) saturate(3955%) hue-rotate(166deg)
    brightness(96%) contrast(88%);
`

const StyledTable = styled.div`
  margin-bottom: 20px;
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  border: solid ${theme.contentBorder};
  border-width: 2px 0;
  > :not(:first-child) {
    border-left: 1px solid ${theme.contentBorder};
    padding-left: 15px;
  }
`

const StyledCell = styled.div`
  padding: 20px 0;
  align-items: left;
`

// TODO: shared
const FieldTitle = styled(Text.Block)`
  color: ${theme.textSecondary};
  text-transform: lowercase;
  font-variant: small-caps;
  font-weight: bold;
  margin-bottom: 6px;
`

const SummaryTable = () => {
  return (
    <StyledTable>
      <StyledCell>
        <FieldTitle>Experience Level</FieldTitle>
        <Text color={theme.textPrimary}>Beginner</Text>
      </StyledCell>

      <StyledCell>
        <FieldTitle>Deadline</FieldTitle>
        <Text>Due in 4 weeks</Text>
      </StyledCell>

      <StyledCell>
        <FieldTitle>Num. Available</FieldTitle>
        <Text>Up to 3</Text>
      </StyledCell>

      <StyledCell>
        <FieldTitle>Status</FieldTitle>
        <Text>Funded</Text>
      </StyledCell>
    </StyledTable>
  )
}

// this 10px padding and...
const Wrapper = styled.div`
  display: flex;
  height: 100%;
  padding: 10px;
`
// todo: wrapper component for different sizes (changes padding mostly)

// ...that 10px margin result in a 20px gap
const cardStyle = {
  flex: '0 1 auto',
  textAlign: 'left',
  padding: '15px 30px',
  margin: '10px',
  background: theme.contentBackground,
  border: `1px solid ${theme.contentBorder}`,
  borderRadius: '3px',
}

const column = {
  display: 'flex',
  flexDirection: 'column',
  flexBasis: '100%',
}

// TODO: Remove fake default value for img
const Avatar = ({ size, img = githubLogo }) => {
  // do something with the size...
  const avatarStyle = () => {
    switch (size) {
    case 'small':
      return { transform: 'scale(.6)' }
    default:
      return { transform: 'scale(.8)' }
    }
  }

  return (
    <div>
      <img src={img} alt="user avatar" style={avatarStyle()} />
    </div>
  )
}

const MemberRow = ({ name, role, status, avatar }) => (
  <Wrapper>
    <Avatar size="normal" style={column}>
      {avatar}
    </Avatar>
    <div style={{ ...column, flex: 2 }}>
      <Text.Block>{name}</Text.Block>
      <Text.Block>{role}</Text.Block>
      <Text.Block>{status}</Text.Block>
    </div>
    <ContextMenu>
      <ContextMenuItem>In progress...</ContextMenuItem>
    </ContextMenu>
  </Wrapper>
)
const ActivityRow = ({ name, log, date, avatar }) => (
  <Wrapper style={{ padding: '0' }}>
    <Avatar size="small" style={column}>
      {avatar}
    </Avatar>
    <div style={{ ...column, flex: 2 }}>
      <Text.Block>
        {name} {log}
      </Text.Block>
      <Text.Block>{date}</Text.Block>
    </div>
  </Wrapper>
)

const fakeActivities = [
  {
    name: 'Worf',
    log: 'began the task',
    date: '2 days ago',
    avatar: null,
  },
  {
    name: 'Tasha Yar',
    log: 'assigned Worf',
    date: '3 days ago',
    avatar: null,
  },
  {
    name: 'Data',
    log: 'rejected Jean-Luc\'s work',
    date: 'Last seen 4 hours ago',
    avatar: null,
  },
]

const fakeMembers = [
  {
    name: 'Worf',
    role: 'Contributor',
    status: 'Pending assignment',
    avatar: null,
  },
  {
    name: 'Tasha Yar',
    role: 'Contributor',
    status: 'Assignment approved',
    avatar: null,
  },
  {
    name: 'Data',
    role: 'Task Manager',
    status: 'Last seen 4 hours ago',
    avatar: null,
  },
]

const Detail = ({
  bountyBadge = '100 ANT',
  title,
  number,
  repo,
  body,
  activities = fakeActivities, // TODO: Remove default fake value when data arrives from backend
  team = fakeMembers, // TODO: Also this
}) => {
  const calculatedDate = () => {
    // something obtained from props and transformed to be like:
    return 'Opened 4 days ago'
  }
  // Some dynamically generated components
  const teamRows = team.map((member, i) => <MemberRow key={i} {...member} />)
  const activityRows = activities.map((data, i) => (
    <ActivityRow key={i} {...data} />
  ))

  console.log('card props:', title)
  return (
    <Wrapper>
      <div style={{ ...column, flex: 3, maxWidth: '705px' }}>
        <div style={cardStyle}>
          <Wrapper style={{ justifyContent: 'space-between' }}>
            <div style={{ ...column, flex: 2, marginRight: '20px' }}>
              <Text.Block size="xlarge" style={{ marginBottom: '10px' }}>
                {title}
              </Text.Block>
              <Text.Block color="#21AAE7" style={{ marginBottom: '10px' }}>
                <GithubLogo src={githubLogo} />
                {repo} #{number}
              </Text.Block>
              <Text.Block
                size="small"
                color={theme.textSecondary}
                style={{ marginBottom: '10px' }}
              >
                {calculatedDate()}
              </Text.Block>
            </div>
            <div style={{ ...column, flex: 0, alignItems: 'flex-end' }}>
              <DropDownButton enabled />
              {/* <Text>$500 USD</Text> */}
              <Badge
                foreground={theme.badgeNotificationBackground}
                background="#D0F2DB"
                style={{ marginTop: '15px' }}
              >
                <Text>{bountyBadge}</Text>
              </Badge>
            </div>
          </Wrapper>
          <SummaryTable />
          <FieldTitle>Description</FieldTitle>
          <Text.Block style={{ marginTop: '20px' }}>{body}</Text.Block>
          <Text.Block>Labels</Text.Block>
        </div>
      </div>
      <div style={{ ...column, flex: 1, maxWidth: '359px' }}>
        <div style={cardStyle}>
          <FieldTitle>Team</FieldTitle>
          {teamRows}
        </div>
        <div style={cardStyle}>
          <FieldTitle>Activity</FieldTitle>
          {activityRows}
        </div>
      </div>
    </Wrapper>
  )
}

export default Detail
