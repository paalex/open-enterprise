import React from 'react'
import styled from 'styled-components'
import { Button, Card, Text } from '@aragon/ui'
import { usePanelManagement } from '../Panel'

import unauthorizedSvg from '../../assets/empty.svg'

const Empty = () => {
  const { setupNewProject } = usePanelManagement()

  return (

    <EmptyCard>
      <div
        css={`
        width: 100%;
        height: 100%;
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: space-evenly;
      `}
      >
        <img css="margin: 10px" src={unauthorizedSvg} alt="" height="160" />
        <Text size="xlarge">
            No projects found
        </Text>
        <Text css="margin-bottom: 6px">
            It seems that you have not set up a project yet
        </Text>
        <Button mode="strong" onClick={setupNewProject}>New project</Button>
      </div>
    </EmptyCard>
  )
}

const EmptyCard = styled(Card)`
  width: 100%;
  height: 384px;
  padding: 28px;
`

export default Empty
